import Darwin
import Foundation

/// State of an individual Darwin kernel thread
public enum ThreadRunState: String, Sendable {
    case running = "Running"
    case stopped = "Stopped"
    case waiting = "Waiting"
    case uninterruptible = "Uninterruptible"
    case halted = "Halted"
    case unknown = "Unknown"

    init(from state: integer_t) {
        switch state {
        case TH_STATE_RUNNING:
            self = .running
        case TH_STATE_STOPPED:
            self = .stopped
        case TH_STATE_WAITING:
            self = .waiting
        case TH_STATE_UNINTERRUPTIBLE:
            self = .uninterruptible
        case TH_STATE_HALTED:
            self = .halted
        default:
            self = .unknown
        }
    }
}

/// Detailed per-thread execution metric captured via Darwin Mach task_threads
public struct ThreadMetric: Sendable, Identifiable {
    public var id: UInt64
    public let name: String
    public let cpuUsagePercent: Double
    public let runState: ThreadRunState
    public let priority: Int32
    public let sleepTimeSeconds: Int32
    public let isMainThread: Bool

    public init(
        id: UInt64,
        name: String,
        cpuUsagePercent: Double,
        runState: ThreadRunState,
        priority: Int32,
        sleepTimeSeconds: Int32,
        isMainThread: Bool
    ) {
        self.id = id
        self.name = name
        self.cpuUsagePercent = cpuUsagePercent
        self.runState = runState
        self.priority = priority
        self.sleepTimeSeconds = sleepTimeSeconds
        self.isMainThread = isMainThread
    }
}

/// Aggregated process thread scheduling summary
public struct ProcessThreadSummary: Sendable {
    public let totalThreads: Int
    public let runningThreads: Int
    public let waitingThreads: Int
    public let globalCPUPercent: Double
    public let topThreads: [ThreadMetric]
    /// Total nanoseconds or ticks spent in wait state
    public let totalWaitStateTime: UInt64
    /// Flag indicating if the main thread is blocked while background threads are consuming CPU
    public let isMainThreadStarved: Bool

    public init(
        totalThreads: Int,
        runningThreads: Int,
        waitingThreads: Int,
        globalCPUPercent: Double,
        topThreads: [ThreadMetric],
        totalWaitStateTime: UInt64,
        isMainThreadStarved: Bool
    ) {
        self.totalThreads = totalThreads
        self.runningThreads = runningThreads
        self.waitingThreads = waitingThreads
        self.globalCPUPercent = globalCPUPercent
        self.topThreads = topThreads
        self.totalWaitStateTime = totalWaitStateTime
        self.isMainThreadStarved = isMainThreadStarved
    }
}

/// Low-level Darwin kernel CPU & Thread Scheduler Monitor
///
/// Implements lightweight thread profiling via Mach task_threads() and thread_info().
/// Solves CPU scheduling opacity and detects priority inversions / lock contentions.
public actor ThreadCPUMonitor {
    public static let shared = ThreadCPUMonitor()

    private var cachedThreadPorts: [thread_act_t] = []
    private var lastScanTime: Date = Date.distantPast
    private let cacheTTL: TimeInterval = 2.0 // Refresh thread port list every 2s to minimize kernel lock contention

    private init() {}

    /// Collect thread-level CPU and scheduling metrics
    public func collectThreadMetrics() -> ProcessThreadSummary {
        let now = Date()
        if now.timeIntervalSince(self.lastScanTime) > self.cacheTTL || self.cachedThreadPorts.isEmpty {
            self.refreshThreadPorts()
            self.lastScanTime = now
        }

        var metrics: [ThreadMetric] = []
        var totalUsage: Double = 0
        var runningCount = 0
        var waitingCount = 0
        var mainThreadMetric: ThreadMetric?

        for (index, port) in self.cachedThreadPorts.enumerated() {
            var basicInfo = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)

            let kr = withUnsafeMutablePointer(to: &basicInfo) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), intPtr, &count)
                }
            }

            guard kr == KERN_SUCCESS else { continue }

            // Extract extended info for thread name and priority
            var extInfo = thread_extended_info()
            var extCount = mach_msg_type_number_t(MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<integer_t>.size)
            let extKr = withUnsafeMutablePointer(to: &extInfo) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(extCount)) { intPtr in
                    thread_info(port, thread_flavor_t(THREAD_EXTENDED_INFO), intPtr, &extCount)
                }
            }

            let name: String
            let priority: Int32
            if extKr == KERN_SUCCESS {
                let rawName = withUnsafePointer(to: extInfo.pth_name) { ptr in
                    String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
                }
                name = rawName.isEmpty ? (index == 0 ? "Main Thread" : "Worker Thread #\(index)") : rawName
                priority = extInfo.pth_priority
            } else {
                name = index == 0 ? "Main Thread" : "Thread #\(index)"
                priority = 0
            }

            // Normalization: TH_USAGE_SCALE is 1000 in Darwin
            let cpuPercent = (Double(basicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
            totalUsage += cpuPercent

            let runState = ThreadRunState(from: basicInfo.run_state)
            if runState == .running { runningCount += 1 }
            if runState == .waiting { waitingCount += 1 }

            let isMain = (index == 0)
            let metric = ThreadMetric(
                id: UInt64(port),
                name: name,
                cpuUsagePercent: cpuPercent,
                runState: runState,
                priority: priority,
                sleepTimeSeconds: basicInfo.sleep_time,
                isMainThread: isMain
            )

            metrics.append(metric)
            if isMain {
                mainThreadMetric = metric
            }
        }

        // Check if main thread is starved (waiting for long while background threads consume > 50% CPU)
        let backgroundUsage = totalUsage - (mainThreadMetric?.cpuUsagePercent ?? 0)
        let mainWaiting = (mainThreadMetric?.runState == .waiting && (mainThreadMetric?.sleepTimeSeconds ?? 0) > 1)
        let isStarved = mainWaiting && (backgroundUsage > 50.0)

        // Query task wait state info if available
        var waitInfo = task_wait_state_info()
        var waitCount = mach_msg_type_number_t(MemoryLayout<task_wait_state_info_data_t>.size / MemoryLayout<integer_t>.size)
        let waitKr = withUnsafeMutablePointer(to: &waitInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(waitCount)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_WAIT_STATE_INFO), intPtr, &waitCount)
            }
        }
        let waitTime = (waitKr == KERN_SUCCESS) ? waitInfo.total_wait_state_time : 0

        // Sort top threads by CPU usage
        let sorted = metrics.sorted { $0.cpuUsagePercent > $1.cpuUsagePercent }

        return ProcessThreadSummary(
            totalThreads: metrics.count,
            runningThreads: runningCount,
            waitingThreads: waitingCount,
            globalCPUPercent: totalUsage,
            topThreads: Array(sorted.prefix(6)),
            totalWaitStateTime: waitTime,
            isMainThreadStarved: isStarved
        )
    }

    /// Refresh cached thread ports safely to prevent memory leaks and kernel lock pressure
    private func refreshThreadPorts() {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let kr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kr == KERN_SUCCESS, let threads = threadList else {
            return
        }

        var ports: [thread_act_t] = []
        ports.reserveCapacity(Int(threadCount))
        for i in 0..<Int(threadCount) {
            ports.append(threads[i])
        }

        // Release previous send rights before caching new thread ports
        for oldPort in self.cachedThreadPorts {
            mach_port_deallocate(mach_task_self_, oldPort)
        }

        // Deallocate the thread array allocated by Mach kernel
        let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<mach_port_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), size)

        self.cachedThreadPorts = ports
    }
}
