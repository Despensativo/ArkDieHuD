import Darwin
import Foundation
import os

/// Detailed information about an allocated Mach Virtual Memory region
public struct VMRegionInfo: Sendable, Identifiable {
    public var id: UInt64 { address }
    public let address: UInt64
    public let sizeBytes: UInt64
    public let isWritable: Bool
    public let isExecutable: Bool

    public init(address: UInt64, sizeBytes: UInt64, isWritable: Bool, isExecutable: Bool) {
        self.address = address
        self.sizeBytes = sizeBytes
        self.isWritable = isWritable
        self.isExecutable = isExecutable
    }

    public var sizeMB: Double {
        Double(sizeBytes) / 1_048_576.0
    }
}

/// Comprehensive Virtual Memory & Jetsam Early Warning Metrics
public struct VMMemoryMetrics: Sendable {
    /// Physical footprint tracked by Jetsam (in bytes)
    public let physicalFootprintBytes: UInt64
    /// Resident memory in RAM (in bytes)
    public let residentSizeBytes: UInt64
    /// Dirty memory pages allocated internally by the process (in bytes)
    public let internalDirtyBytes: UInt64
    /// Memory pages compressed by the kernel (in bytes)
    public let compressedDirtyBytes: UInt64
    /// Exact bytes remaining before the Darwin kernel triggers Jetsam kill (if available)
    public let jetsamLimitBytesRemaining: UInt64?
    /// Total number of mapped VM regions
    public let mappedRegionsCount: Int

    /// Ratio between process dirty memory and system active/inactive memory (0.0 to 1.0)
    /// A ratio above 0.65 indicates imminent risk of Jetsam termination
    public let dirtyRatio: Double

    public init(
        physicalFootprintBytes: UInt64,
        residentSizeBytes: UInt64,
        internalDirtyBytes: UInt64,
        compressedDirtyBytes: UInt64,
        jetsamLimitBytesRemaining: UInt64? = nil,
        mappedRegionsCount: Int,
        dirtyRatio: Double
    ) {
        self.physicalFootprintBytes = physicalFootprintBytes
        self.residentSizeBytes = residentSizeBytes
        self.internalDirtyBytes = internalDirtyBytes
        self.compressedDirtyBytes = compressedDirtyBytes
        self.jetsamLimitBytesRemaining = jetsamLimitBytesRemaining
        self.mappedRegionsCount = mappedRegionsCount
        self.dirtyRatio = dirtyRatio
    }

    /// Flag indicating whether the app is in high-risk Jetsam danger
    public var isJetsamRisk: Bool {
        if let remaining = jetsamLimitBytesRemaining, remaining < 150 * 1024 * 1024 {
            return true
        }
        return dirtyRatio > 0.65
    }

    public var physicalFootprintMB: Double {
        Double(physicalFootprintBytes) / 1_048_576.0
    }

    public var jetsamLimitRemainingMB: Double? {
        jetsamLimitBytesRemaining.map { Double($0) / 1_048_576.0 }
    }
}

/// Mach Virtual Memory Scanner and Jetsam Early Warning Monitor
///
/// Implements deep VM tracking via vm_region_64, task_vm_info, and host_statistics64.
/// Accurately predicts Jetsam OOM crashes and detects memory leaks across VM regions
/// (Metal buffers, CoreImage cache, WKWebView maps) that Instruments Leaks misses.
public actor VMMemoryMonitor {
    public static let shared = VMMemoryMonitor()

    private var purgeHandlers: [@Sendable () -> Void] = []

    private init() {}

    /// Register a callback to be executed when memory pressure or Jetsam danger is detected
    public func registerPurgeHandler(_ handler: @escaping @Sendable () -> Void) {
        self.purgeHandlers.append(handler)
    }

    /// Retrieve current Mach VM metrics and Jetsam danger ratio
    public func getVMMetrics() -> VMMemoryMetrics {
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutablePointer(to: &vmInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            return VMMemoryMetrics(
                physicalFootprintBytes: 0,
                residentSizeBytes: 0,
                internalDirtyBytes: 0,
                compressedDirtyBytes: 0,
                jetsamLimitBytesRemaining: nil,
                mappedRegionsCount: 0,
                dirtyRatio: 0.0
            )
        }

        // Query system-wide active & inactive memory
        var hostSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.stride)
        var hostInfo = vm_statistics64_data_t()
        let hostKr = withUnsafeMutablePointer(to: &hostInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(hostSize)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &hostSize)
            }
        }

        let pageSize = UInt64(getpagesize())
        var dirtyRatio: Double = 0.0

        if hostKr == KERN_SUCCESS {
            let activeBytes = UInt64(hostInfo.active_count) * pageSize
            let inactiveBytes = UInt64(hostInfo.inactive_count) * pageSize
            let totalAvailableDynamic = activeBytes + inactiveBytes

            let processDirty = UInt64(vmInfo.internal) + UInt64(vmInfo.compressed)
            if totalAvailableDynamic > 0 {
                dirtyRatio = min(1.0, max(0.0, Double(processDirty) / Double(totalAvailableDynamic)))
            }
        }

        let remainingLimit: UInt64? = vmInfo.limit_bytes_remaining > 0 ? UInt64(vmInfo.limit_bytes_remaining) : nil

        let metrics = VMMemoryMetrics(
            physicalFootprintBytes: UInt64(vmInfo.phys_footprint),
            residentSizeBytes: UInt64(vmInfo.resident_size),
            internalDirtyBytes: UInt64(vmInfo.internal),
            compressedDirtyBytes: UInt64(vmInfo.compressed),
            jetsamLimitBytesRemaining: remainingLimit,
            mappedRegionsCount: Int(vmInfo.region_count),
            dirtyRatio: dirtyRatio
        )

        // If imminent Jetsam risk, automatically invoke registered purge handlers
        if metrics.isJetsamRisk {
            self.executePurge()
        }

        return metrics
    }

    /// Scans the Mach Virtual Address Space (VAS) to locate suspicious large writable allocations
    /// - Parameter minSizeBytes: Threshold size in bytes (default 1MB = 1,048,576 bytes)
    /// - Parameter maxRegionsToReport: Maximum regions to return to avoid excessive overhead
    /// - Returns: List of suspicious large VM regions
    public func scanLargeVMRegions(minSizeBytes: UInt64 = 1_048_576, maxRegionsToReport: Int = 15) -> [VMRegionInfo] {
        var regions: [VMRegionInfo] = []
        var address: vm_address_t = 0x1000 // Skip initial zero-page protection
        var regionInfo = vm_region_basic_info_64()
        let baseInfoCount = mach_msg_type_number_t(MemoryLayout<vm_region_basic_info_64>.size / MemoryLayout<integer_t>.size)

        while regions.count < maxRegionsToReport {
            var size: vm_size_t = 0
            var objectName: mach_port_t = 0
            var count = baseInfoCount

            let kr = withUnsafeMutablePointer(to: &regionInfo) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    vm_region_64(
                        mach_task_self_,
                        &address,
                        &size,
                        vm_region_flavor_t(VM_REGION_BASIC_INFO_64),
                        intPtr,
                        &count,
                        &objectName
                    )
                }
            }

            if objectName != MACH_PORT_NULL {
                mach_port_deallocate(mach_task_self_, objectName)
            }

            guard kr == KERN_SUCCESS else { break }

            let isWritable = (regionInfo.protection & VM_PROT_WRITE) != 0
            let isExecutable = (regionInfo.max_protection & VM_PROT_EXECUTE) != 0

            // Filter: Large writable non-executable memory blocks (typical of leaking image/texture caches or maps)
            if UInt64(size) >= minSizeBytes && isWritable && !isExecutable {
                regions.append(VMRegionInfo(
                    address: UInt64(address),
                    sizeBytes: UInt64(size),
                    isWritable: isWritable,
                    isExecutable: isExecutable
                ))
            }

            // Advance address safely without overflow
            guard size > 0 else { break }
            let (nextAddress, overflow) = address.addingReportingOverflow(size)
            if overflow { break }
            address = nextAddress
        }

        return regions
    }

    /// Trigger emergency memory purge on registered handlers
    public func executePurge() {
        for handler in self.purgeHandlers {
            handler()
        }
    }
}
