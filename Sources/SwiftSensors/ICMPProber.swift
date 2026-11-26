import Darwin
import Foundation
import Network
import os

/// Low-level BSD socket ICMP/UDP datagram prober, TCP handshake prober, DNS cache, and interface/VPN inspector.
enum ICMPProber {
    private enum ResolvedDatagramAddress: Sendable {
        case v4(UInt32)
        case v6(in6_addr, scopeID: UInt32)

        var family: Int32 {
            switch self {
            case .v4: return AF_INET
            case .v6: return AF_INET6
            }
        }
    }

    private static let dnsCache = OSAllocatedUnfairLock<[String: ResolvedDatagramAddress]>(initialState: [:])
    private static let icmpEchoType: UInt8 = 8
    private static let icmpEchoReplyType: UInt8 = 0
    private static let icmp6EchoType: UInt8 = 128
    private static let icmp6EchoReplyType: UInt8 = 129

    static func clearDNSCache() {
        self.dnsCache.withLock { $0.removeAll() }
    }

    // MARK: - Non-Privileged Darwin ICMP/ICMPv6 & UDP/DNS Datagram Probes

    /// Sends a single ICMP (IPv4) or ICMPv6 (IPv6) Echo Request using a non-privileged Darwin datagram socket.
    static func pingICMP(
        host: String,
        sequence: UInt16,
        timeout: TimeInterval,
        allowIPv6: Bool = false
    ) async -> Double? {
        await Self.sendDatagramAndAwaitReply(
            host: host,
            port: 0,
            allowIPv6: allowIPv6,
            timeout: timeout,
            prepareSocketPayload: { resolved in
                switch resolved {
                case .v4:
                    return (IPPROTO_ICMP, Self.makeICMPEchoPacket(identifier: 0x5353, sequence: sequence))
                case .v6:
                    return (IPPROTO_ICMPV6, Self.makeICMPv6EchoPacket(identifier: 0x5353, sequence: sequence))
                }
            },
            matchesReply: { resolved, recvBuffer, count, _ in
                switch resolved {
                case .v4:
                    var icmpOffset = 0
                    if (recvBuffer[0] >> 4) == 4 && count >= 28 {
                        let ihl = Int(recvBuffer[0] & 0x0F) * 4
                        if ihl >= 20 && count >= ihl + 8 {
                            icmpOffset = ihl
                        }
                    }
                    guard count >= icmpOffset + 8 else { return false }
                    let replyType = recvBuffer[icmpOffset]
                    let replyCode = recvBuffer[icmpOffset + 1]
                    let replySeq = (UInt16(recvBuffer[icmpOffset + 6]) << 8) | UInt16(recvBuffer[icmpOffset + 7])
                    return replyType == Self.icmpEchoReplyType && replyCode == 0 && replySeq == sequence

                case .v6:
                    // Darwin SOCK_DGRAM IPPROTO_ICMPV6 delivers the ICMPv6 header starting at index 0.
                    guard count >= 8 else { return false }
                    let replyType = recvBuffer[0]
                    let replyCode = recvBuffer[1]
                    let replySeq = (UInt16(recvBuffer[6]) << 8) | UInt16(recvBuffer[7])
                    return replyType == Self.icmp6EchoReplyType && replyCode == 0 && replySeq == sequence
                }
            }
        )
    }

    /// Sends a minimal 17-byte RFC 1035 DNS root NS query over UDP (default port 53) on IPv4 or IPv6.
    static func pingUDPDNS(
        host: String,
        port: UInt16 = 53,
        transactionID: UInt16,
        timeout: TimeInterval,
        allowIPv6: Bool = false
    ) async -> Double? {
        let query = Self.makeDNSRootNSQuery(transactionID: transactionID)
        let expectedPort = port.bigEndian
        return await Self.sendDatagramAndAwaitReply(
            host: host,
            port: port,
            allowIPv6: allowIPv6,
            timeout: timeout,
            prepareSocketPayload: { _ in (IPPROTO_UDP, query) },
            matchesReply: { _, recvBuffer, count, srcPortBigEndian in
                guard count >= 12, srcPortBigEndian == expectedPort else { return false }
                let replyID = (UInt16(recvBuffer[0]) << 8) | UInt16(recvBuffer[1])
                let isDNSResponse = (recvBuffer[2] & 0x80) != 0
                return isDNSResponse && replyID == transactionID
            }
        )
    }

    /// Shared non-blocking poll() loop on a GCD queue supporting both AF_INET and AF_INET6.
    private static func sendDatagramAndAwaitReply(
        host: String,
        port: UInt16,
        allowIPv6: Bool,
        timeout: TimeInterval,
        prepareSocketPayload: @escaping @Sendable (ResolvedDatagramAddress) -> (ipProtocol: Int32, payload: [UInt8]),
        matchesReply: @escaping @Sendable (ResolvedDatagramAddress, [UInt8], Int, UInt16) -> Bool
    ) async -> Double? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let resolved = Self.resolveDatagramAddress(host: trimmedHost, allowIPv6: allowIPv6) else {
                    continuation.resume(returning: nil)
                    return
                }

                let (ipProtocol, payload) = prepareSocketPayload(resolved)
                let fd = socket(resolved.family, SOCK_DGRAM, ipProtocol)
                guard fd >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { close(fd) }

                var noSigPipe: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

                var (destStorage, destLen) = Self.makeSockAddrStorage(for: resolved, port: port)
                let startNs = DispatchTime.now().uptimeNanoseconds

                let sent = payload.withUnsafeBytes { rawBuf -> ssize_t in
                    withUnsafePointer(to: &destStorage) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                            sendto(fd, rawBuf.baseAddress, rawBuf.count, 0, sockPtr, destLen)
                        }
                    }
                }

                guard sent == payload.count else {
                    continuation.resume(returning: nil)
                    return
                }

                let timeoutNs = UInt64(max(0.1, timeout) * 1_000_000_000)
                let deadlineNs = startNs &+ timeoutNs
                var recvBuffer = [UInt8](repeating: 0, count: 512)

                while true {
                    let nowNs = DispatchTime.now().uptimeNanoseconds
                    if nowNs >= deadlineNs {
                        continuation.resume(returning: nil)
                        return
                    }

                    let remainingMs = max(1, Int32((deadlineNs - nowNs) / 1_000_000))
                    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    let pollResult = poll(&pfd, 1, remainingMs)

                    if pollResult == 0 {
                        continuation.resume(returning: nil)
                        return
                    }
                    if pollResult < 0 {
                        if errno == EINTR { continue }
                        continuation.resume(returning: nil)
                        return
                    }

                    var srcStorage = sockaddr_storage()
                    var srcLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                    let bytesRead = recvBuffer.withUnsafeMutableBytes { rawBuf -> ssize_t in
                        withUnsafeMutablePointer(to: &srcStorage) { addrPtr in
                            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                                recvfrom(fd, rawBuf.baseAddress, rawBuf.count, 0, sockPtr, &srcLen)
                            }
                        }
                    }

                    guard bytesRead > 0 else {
                        continuation.resume(returning: nil)
                        return
                    }

                    guard let srcPortBigEndian = Self.matchingSourcePort(srcStorage, expected: resolved) else {
                        continue
                    }

                    if matchesReply(resolved, recvBuffer, Int(bytesRead), srcPortBigEndian) {
                        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0
                        continuation.resume(returning: elapsedMs)
                        return
                    }
                }
            }
        }
    }

    // MARK: - TCP Handshake Probe (Fallback or Explicit Port Check)

    static func pingTCP(
        host: String,
        port: UInt16,
        timeout: TimeInterval,
        allowIPv6: Bool = false
    ) async -> Double? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return nil
        }

        if !allowIPv6, Self.isIPv6Literal(trimmedHost) {
            return nil
        }

        let params = NWParameters.tcp
        if !allowIPv6, let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let endpointHost = NWEndpoint.Host(trimmedHost)
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: params)
        let start = DispatchTime.now()

        return await withCheckedContinuation { continuation in
            let isDone = OSAllocatedUnfairLock(initialState: false)
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                isDone.withLock { done in
                    if !done {
                        done = true
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
                    isDone.withLock { done in
                        if !done {
                            done = true
                            timeoutTask.cancel()
                            connection.cancel()
                            continuation.resume(returning: elapsed)
                        }
                    }
                case .failed, .cancelled:
                    isDone.withLock { done in
                        if !done {
                            done = true
                            timeoutTask.cancel()
                            continuation.resume(returning: nil)
                        }
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - Interface Byte Counters & Local Route / Gateway / VPN Inspection

    static func readInterfaceBytes() -> (bytesIn: UInt64, bytesOut: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            guard let ifaNamePtr = cur.pointee.ifa_name,
                  let ifaAddr = cur.pointee.ifa_addr else {
                ptr = cur.pointee.ifa_next
                continue
            }
            let flags = Int32(cur.pointee.ifa_flags)
            let name = String(cString: ifaNamePtr)

            if (flags & IFF_UP) != 0 && (name.hasPrefix("en") || name.hasPrefix("pdp_ip")) {
                if ifaAddr.pointee.sa_family == UInt8(AF_LINK), let data = cur.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self)
                    totalIn += UInt64(ifData.pointee.ifi_ibytes)
                    totalOut += UInt64(ifData.pointee.ifi_obytes)
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return (totalIn, totalOut)
    }

    static func inspectLocalInterfaces(
        wiredInterfaceNames: Set<String> = [],
        wifiInterfaceNames: Set<String> = [],
        isWiredPath: Bool = false,
        preferUSBEthernet: Bool = true
    ) -> (
        localIPv4: String?,
        detectedGatewayIP: String?,
        vpnInterface: String?,
        activeInterfaceName: String?,
        usbEthernetIPv4: String?,
        localIPv6: String?
    ) {
        struct InterfaceCandidate {
            var ipv4: String?
            var gatewayIPv4: String?
            var globalIPv6: String?
            var ulaIPv6: String?

            var preferredIPv6: String? { self.globalIPv6 ?? self.ulaIPv6 }
            var hasUsableAddress: Bool { self.ipv4 != nil || self.preferredIPv6 != nil }
        }

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (nil, nil, nil, nil, nil, nil)
        }
        defer { freeifaddrs(ifaddr) }

        var candidates: [String: InterfaceCandidate] = [:]
        var activeVPNName: String?

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            guard let ifaNamePtr = cur.pointee.ifa_name,
                  let ifaAddr = cur.pointee.ifa_addr else {
                ptr = cur.pointee.ifa_next
                continue
            }

            let flags = Int32(cur.pointee.ifa_flags)
            let isUpAndRunning = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let name = String(cString: ifaNamePtr)
            let family = ifaAddr.pointee.sa_family

            if isUpAndRunning && family == UInt8(AF_INET) {
                let addrIn = ifaAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                let ipHostOrder = UInt32(bigEndian: addrIn.sin_addr.s_addr)
                let ipString = Self.ipv4String(fromHostOrder: ipHostOrder)

                if !ipString.hasPrefix("169.254.") && !ipString.hasPrefix("127.") {
                    if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                        if activeVPNName == nil { activeVPNName = name }
                    } else if name.hasPrefix("en") {
                        var candidate = candidates[name] ?? InterfaceCandidate()
                        candidate.ipv4 = ipString
                        if let maskAddr = cur.pointee.ifa_netmask,
                           maskAddr.pointee.sa_family == UInt8(AF_INET) {
                            let maskIn = maskAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                            let maskHostOrder = UInt32(bigEndian: maskIn.sin_addr.s_addr)
                            let gwHostOrder = (ipHostOrder & maskHostOrder) | 1
                            if gwHostOrder != ipHostOrder {
                                candidate.gatewayIPv4 = Self.ipv4String(fromHostOrder: gwHostOrder)
                            }
                        }
                        candidates[name] = candidate
                    }
                }
            } else if isUpAndRunning && family == UInt8(AF_INET6) {
                let addrIn6 = ifaAddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                if let ip6 = Self.ipv6String(from: addrIn6.sin6_addr) {
                    let lower = ip6.lowercased()
                    let isIgnorable = (lower == "::" || lower == "::1" || lower.hasPrefix("fe80:") || lower.hasPrefix("ff"))
                    if !isIgnorable {
                        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                            if activeVPNName == nil { activeVPNName = name }
                        } else if name.hasPrefix("en") {
                            var candidate = candidates[name] ?? InterfaceCandidate()
                            if lower.hasPrefix("fc") || lower.hasPrefix("fd") {
                                if candidate.ulaIPv6 == nil { candidate.ulaIPv6 = ip6 }
                            } else if candidate.globalIPv6 == nil {
                                candidate.globalIPv6 = ip6
                            }
                            candidates[name] = candidate
                        }
                    }
                }
            }

            ptr = cur.pointee.ifa_next
        }

        let wifiSearchOrder = (Array(wifiInterfaceNames) + ["en0"]).reduce(into: [String]()) { order, name in
            if !order.contains(name) { order.append(name) }
        }
        let wifiIface = wifiSearchOrder.first { candidates[$0]?.ipv4 != nil }
            ?? wifiSearchOrder.first { candidates[$0]?.hasUsableAddress == true }

        let explicitWiredIPv4Match = wiredInterfaceNames.sorted().first { candidates[$0]?.ipv4 != nil }
        let fallbackWiredIPv4Match = isWiredPath
            ? candidates.keys.sorted().first { $0 != "en0" && !wifiInterfaceNames.contains($0) && candidates[$0]?.ipv4 != nil }
            : nil
        let wiredIPv6OnlyMatch = isWiredPath
            ? (wiredInterfaceNames.sorted().first { candidates[$0]?.hasUsableAddress == true }
                ?? candidates.keys.sorted().first { $0 != "en0" && !wifiInterfaceNames.contains($0) && candidates[$0]?.hasUsableAddress == true })
            : nil
        let usbIface = explicitWiredIPv4Match ?? fallbackWiredIPv4Match ?? wiredIPv6OnlyMatch
        let usbEthernetIPv4 = usbIface.flatMap { candidates[$0]?.ipv4 }

        let chosenIface: String?
        if preferUSBEthernet {
            chosenIface = usbIface
                ?? wifiIface
                ?? candidates.keys.sorted().first { candidates[$0]?.ipv4 != nil }
                ?? candidates.keys.sorted().first { candidates[$0]?.hasUsableAddress == true }
        } else {
            let blockedWired = usbIface.map { wiredInterfaceNames.union([$0]) } ?? wiredInterfaceNames
            chosenIface = wifiIface
                ?? candidates.keys.sorted().first { !blockedWired.contains($0) && candidates[$0]?.ipv4 != nil }
                ?? candidates.keys.sorted().first { !blockedWired.contains($0) && candidates[$0]?.hasUsableAddress == true }
        }

        let chosen = chosenIface.flatMap { candidates[$0] }
        return (
            chosen?.ipv4,
            chosen?.gatewayIPv4,
            activeVPNName,
            chosenIface,
            usbEthernetIPv4,
            chosen?.preferredIPv6
        )
    }

    // MARK: - Helpers

    private static func isIPv6Literal(_ host: String) -> Bool {
        let base = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        var addr6 = in6_addr()
        return inet_pton(AF_INET6, base, &addr6) == 1
    }

    private static func resolveDatagramAddress(host: String, allowIPv6: Bool) -> ResolvedDatagramAddress? {
        var direct4 = in_addr()
        if inet_pton(AF_INET, host, &direct4) == 1 {
            return .v4(direct4.s_addr)
        }

        if allowIPv6 {
            let parts = host.split(separator: "%", maxSplits: 1).map(String.init)
            let baseHost = parts.first ?? host
            var direct6 = in6_addr()
            if inet_pton(AF_INET6, baseHost, &direct6) == 1 {
                let scopeID: UInt32 = (parts.count == 2) ? UInt32(if_nametoindex(parts[1])) : 0
                return .v6(direct6, scopeID: scopeID)
            }
        } else if Self.isIPv6Literal(host) {
            return nil
        }

        let cacheKey = "\(host)|\(allowIPv6 ? 6 : 4)"
        if let cached = self.dnsCache.withLock({ $0[cacheKey] }) {
            return cached
        }

        var hints = addrinfo()
        hints.ai_family = allowIPv6 ? AF_UNSPEC : AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else {
            return nil
        }
        defer { freeaddrinfo(res) }

        var firstV4: ResolvedDatagramAddress?
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            if entry.pointee.ai_family == AF_INET6, allowIPv6, let addr = entry.pointee.ai_addr {
                let sin6 = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                let resolved = ResolvedDatagramAddress.v6(sin6.sin6_addr, scopeID: sin6.sin6_scope_id)
                self.dnsCache.withLock { $0[cacheKey] = resolved }
                return resolved
            } else if entry.pointee.ai_family == AF_INET, firstV4 == nil, let addr = entry.pointee.ai_addr {
                let sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                firstV4 = .v4(sin.sin_addr.s_addr)
            }
            cursor = entry.pointee.ai_next
        }

        if let firstV4 {
            self.dnsCache.withLock { $0[cacheKey] = firstV4 }
            return firstV4
        }
        return nil
    }

    private static func makeSockAddrStorage(
        for resolved: ResolvedDatagramAddress,
        port: UInt16
    ) -> (sockaddr_storage, socklen_t) {
        var storage = sockaddr_storage()
        switch resolved {
        case .v4(let addrBigEndian):
            var dest = sockaddr_in()
            dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_port = port.bigEndian
            dest.sin_addr = in_addr(s_addr: addrBigEndian)
            withUnsafeMutablePointer(to: &storage) { storagePtr in
                storagePtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee = dest }
            }
            return (storage, socklen_t(MemoryLayout<sockaddr_in>.size))

        case .v6(let addr6, let scopeID):
            var dest = sockaddr_in6()
            dest.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            dest.sin6_family = sa_family_t(AF_INET6)
            dest.sin6_port = port.bigEndian
            dest.sin6_addr = addr6
            dest.sin6_scope_id = scopeID
            withUnsafeMutablePointer(to: &storage) { storagePtr in
                storagePtr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee = dest }
            }
            return (storage, socklen_t(MemoryLayout<sockaddr_in6>.size))
        }
    }

    private static func matchingSourcePort(
        _ storage: sockaddr_storage,
        expected: ResolvedDatagramAddress
    ) -> UInt16? {
        var copy = storage
        switch expected {
        case .v4(let expectedAddr):
            guard copy.ss_family == sa_family_t(AF_INET) else { return nil }
            let src = withUnsafePointer(to: &copy) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            }
            return src.sin_addr.s_addr == expectedAddr ? src.sin_port : nil

        case .v6(let expectedAddr6, _):
            guard copy.ss_family == sa_family_t(AF_INET6) else { return nil }
            let src = withUnsafePointer(to: &copy) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            }
            var lhs = expectedAddr6
            var rhs = src.sin6_addr
            guard memcmp(&lhs, &rhs, MemoryLayout<in6_addr>.size) == 0 else { return nil }
            return src.sin6_port
        }
    }

    private static func makeICMPEchoPacket(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        Self.makeEchoPayload(type: Self.icmpEchoType, identifier: identifier, sequence: sequence, computeChecksum: true)
    }

    private static func makeICMPv6EchoPacket(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        // Kernel fills the ICMPv6 pseudo-header checksum automatically for SOCK_DGRAM IPPROTO_ICMPV6.
        Self.makeEchoPayload(type: Self.icmp6EchoType, identifier: identifier, sequence: sequence, computeChecksum: false)
    }

    private static func makeEchoPayload(
        type: UInt8,
        identifier: UInt16,
        sequence: UInt16,
        computeChecksum: Bool
    ) -> [UInt8] {
        var bytes: [UInt8] = [
            type, 0, // Echo Request Type, Code 0
            0, 0, // Checksum placeholder
            UInt8(identifier >> 8), UInt8(identifier & 0xFF),
            UInt8(sequence >> 8), UInt8(sequence & 0xFF),
            0x53, 0x53, 0x4E, 0x53, // "SSNS"
            0x30, 0x31, 0x30, 0x31,
        ]
        guard computeChecksum else { return bytes }

        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum += (UInt32(bytes[i]) << 8) | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count {
            sum += UInt32(bytes[i]) << 8
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        let checksum = ~UInt16(sum & 0xFFFF)
        bytes[2] = UInt8(checksum >> 8)
        bytes[3] = UInt8(checksum & 0xFF)
        return bytes
    }

    private static func makeDNSRootNSQuery(transactionID: UInt16) -> [UInt8] {
        [
            UInt8(transactionID >> 8), UInt8(transactionID & 0xFF),
            0x01, 0x00, // Standard query, RD=1
            0x00, 0x01, // QDCOUNT=1
            0x00, 0x00, // ANCOUNT=0
            0x00, 0x00, // NSCOUNT=0
            0x00, 0x00, // ARCOUNT=0
            0x00, // QNAME = "." (root)
            0x00, 0x02, // QTYPE = NS
            0x00, 0x01, // QCLASS = IN
        ]
    }

    private static func ipv4String(fromHostOrder addr: UInt32) -> String {
        let b1 = (addr >> 24) & 0xFF
        let b2 = (addr >> 16) & 0xFF
        let b3 = (addr >> 8) & 0xFF
        let b4 = addr & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }

    private static func ipv6String(from addr: in6_addr) -> String? {
        var copy = addr
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &copy, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
            return nil
        }
        let utf8Bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: utf8Bytes, as: UTF8.self)
    }
}
