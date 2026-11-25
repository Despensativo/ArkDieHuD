import Darwin
import Foundation
import Network
import os

/// Low-level BSD socket ICMP/UDP datagram prober, TCP handshake prober, DNS cache, and interface/VPN inspector.
enum ICMPProber {
    private static let dnsCache = OSAllocatedUnfairLock<[String: UInt32]>(initialState: [:])
    private static let icmpEchoType: UInt8 = 8
    private static let icmpEchoReplyType: UInt8 = 0

    static func clearDNSCache() {
        self.dnsCache.withLock { $0.removeAll() }
    }

    // MARK: - Non-Privileged Darwin ICMP & UDP/DNS Datagram Probes

    /// Sends a single IPv4 ICMP Echo Request using a non-privileged Darwin datagram socket.
    static func pingICMP(host: String, sequence: UInt16, timeout: TimeInterval) async -> Double? {
        let packet = Self.makeICMPEchoPacket(identifier: 0x5353, sequence: sequence)
        return await Self.sendDatagramAndAwaitReply(
            host: host,
            port: 0,
            ipProtocol: IPPROTO_ICMP,
            timeout: timeout,
            payload: packet
        ) { recvBuffer, count, _ in
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
        }
    }

    /// Sends a minimal 17-byte RFC 1035 DNS root NS query over UDP (default port 53) to measure real UDP RTT.
    static func pingUDPDNS(host: String, port: UInt16 = 53, transactionID: UInt16, timeout: TimeInterval) async -> Double? {
        let query = Self.makeDNSRootNSQuery(transactionID: transactionID)
        let expectedPort = port.bigEndian
        return await Self.sendDatagramAndAwaitReply(
            host: host,
            port: port,
            ipProtocol: IPPROTO_UDP,
            timeout: timeout,
            payload: query
        ) { recvBuffer, count, srcAddr in
            guard count >= 12, srcAddr.sin_port == expectedPort else { return false }
            let replyID = (UInt16(recvBuffer[0]) << 8) | UInt16(recvBuffer[1])
            let isDNSResponse = (recvBuffer[2] & 0x80) != 0
            return isDNSResponse && replyID == transactionID
        }
    }

    /// Shared non-blocking poll() loop on a GCD queue so BSD I/O never stalls Swift concurrency.
    private static func sendDatagramAndAwaitReply(
        host: String,
        port: UInt16,
        ipProtocol: Int32,
        timeout: TimeInterval,
        payload: [UInt8],
        matchesReply: @escaping @Sendable ([UInt8], Int, sockaddr_in) -> Bool
    ) async -> Double? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let resolvedAddrBigEndian = Self.resolveIPv4BigEndian(host: trimmedHost) else {
                    continuation.resume(returning: nil)
                    return
                }

                let fd = socket(AF_INET, SOCK_DGRAM, ipProtocol)
                guard fd >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { close(fd) }

                var noSigPipe: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

                var destAddr = sockaddr_in()
                destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                destAddr.sin_family = sa_family_t(AF_INET)
                destAddr.sin_port = port.bigEndian
                destAddr.sin_addr = in_addr(s_addr: resolvedAddrBigEndian)

                let startNs = DispatchTime.now().uptimeNanoseconds

                let sent = payload.withUnsafeBytes { rawBuf -> ssize_t in
                    withUnsafePointer(to: &destAddr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                            sendto(
                                fd,
                                rawBuf.baseAddress,
                                rawBuf.count,
                                0,
                                sockPtr,
                                socklen_t(MemoryLayout<sockaddr_in>.size)
                            )
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

                    var srcAddr = sockaddr_in()
                    var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let bytesRead = recvBuffer.withUnsafeMutableBytes { rawBuf -> ssize_t in
                        withUnsafeMutablePointer(to: &srcAddr) { addrPtr in
                            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                                recvfrom(fd, rawBuf.baseAddress, rawBuf.count, 0, sockPtr, &srcLen)
                            }
                        }
                    }

                    guard bytesRead > 0 else {
                        continuation.resume(returning: nil)
                        return
                    }

                    if srcAddr.sin_addr.s_addr != resolvedAddrBigEndian {
                        continue
                    }

                    if matchesReply(recvBuffer, Int(bytesRead), srcAddr) {
                        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0
                        continuation.resume(returning: elapsedMs)
                        return
                    }
                }
            }
        }
    }

    // MARK: - TCP Handshake Probe (Fallback or Explicit Port Check)

    static func pingTCP(host: String, port: UInt16, timeout: TimeInterval) async -> Double? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return nil
        }

        let endpointHost = NWEndpoint.Host(trimmedHost)
        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
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

    static func inspectLocalInterfaces() -> (
        localIPv4: String?,
        detectedGatewayIP: String?,
        vpnInterface: String?
    ) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (nil, nil, nil)
        }
        defer { freeifaddrs(ifaddr) }

        var bestLocalIP: String?
        var bestGatewayIP: String?
        var foundPrimaryEn0 = false
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

            if isUpAndRunning && ifaAddr.pointee.sa_family == UInt8(AF_INET) {
                let addrIn = ifaAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                let ipHostOrder = UInt32(bigEndian: addrIn.sin_addr.s_addr)
                let ipString = Self.ipv4String(fromHostOrder: ipHostOrder)

                if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
                    if !ipString.hasPrefix("127.") && !ipString.hasPrefix("169.254.") {
                        if activeVPNName == nil {
                            activeVPNName = name
                        }
                    }
                } else if name.hasPrefix("en") && !ipString.hasPrefix("169.254.") && !ipString.hasPrefix("127.") {
                    var computedGateway: String?
                    if let maskAddr = cur.pointee.ifa_netmask,
                       maskAddr.pointee.sa_family == UInt8(AF_INET) {
                        let maskIn = maskAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                        let maskHostOrder = UInt32(bigEndian: maskIn.sin_addr.s_addr)
                        let gwHostOrder = (ipHostOrder & maskHostOrder) | 1
                        if gwHostOrder != ipHostOrder {
                            computedGateway = Self.ipv4String(fromHostOrder: gwHostOrder)
                        }
                    }

                    if name == "en0" || !foundPrimaryEn0 {
                        bestLocalIP = ipString
                        if let computedGateway {
                            bestGatewayIP = computedGateway
                        }
                        if name == "en0" {
                            foundPrimaryEn0 = true
                        }
                    }
                }
            }

            ptr = cur.pointee.ifa_next
        }

        return (bestLocalIP, bestGatewayIP, activeVPNName)
    }

    // MARK: - Helpers

    private static func resolveIPv4BigEndian(host: String) -> UInt32? {
        var direct = in_addr()
        if inet_pton(AF_INET, host, &direct) == 1 {
            return direct.s_addr
        }

        if let cached = self.dnsCache.withLock({ $0[host] }) {
            return cached
        }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else {
            return nil
        }
        defer { freeaddrinfo(res) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            if entry.pointee.ai_family == AF_INET,
               let addr = entry.pointee.ai_addr {
                let sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                let resolved = sin.sin_addr.s_addr
                self.dnsCache.withLock { $0[host] = resolved }
                return resolved
            }
            cursor = entry.pointee.ai_next
        }
        return nil
    }

    private static func makeICMPEchoPacket(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var bytes: [UInt8] = [
            Self.icmpEchoType, 0, // Type 8 (Echo), Code 0
            0, 0, // Checksum placeholder
            UInt8(identifier >> 8), UInt8(identifier & 0xFF),
            UInt8(sequence >> 8), UInt8(sequence & 0xFF),
            0x53, 0x53, 0x4E, 0x53, // "SSNS"
            0x30, 0x31, 0x30, 0x31,
        ]

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
}
