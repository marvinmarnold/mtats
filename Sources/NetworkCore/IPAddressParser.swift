// SPDX-License-Identifier: MIT
import Foundation
import Darwin

public struct IPAddressParser {
    /// Reads getifaddrs() once. Returns both the IPv4 address of the first active,
    /// non-loopback interface and the raw byte counters for every interface.
    public static func readCurrentState() -> (localIPv4: String?, counters: [InterfaceCounters]) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return (nil, []) }
        defer { freeifaddrs(ifaddrPtr) }

        var localIPv4: String?
        var countersByName: [String: (rx: UInt64, tx: UInt64)] = [:]

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let name = String(cString: current.pointee.ifa_name)

            // getifaddrs(3) permits ifa_addr to be NULL (e.g. an interface with no configured
            // address) — dereferencing it unconditionally crashes the Host. Skip this entry's
            // address-family-specific handling, not the whole loop (ifa_next still advances).
            if let addr = current.pointee.ifa_addr {
                let family = addr.pointee.sa_family

                if family == UInt8(AF_INET), (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, localIPv4 == nil {
                    var sockAddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    inet_ntop(AF_INET, &sockAddr.sin_addr, &buffer, socklen_t(buffer.count))
                    localIPv4 = String(cString: buffer)
                }

                // Exclude loopback from the throughput total — a reasonable person watching
                // "network usage" doesn't expect local-only traffic (dev servers, Docker,
                // databases) counted as network activity.
                if family == UInt8(AF_LINK), (flags & IFF_LOOPBACK) == 0, let data = current.pointee.ifa_data {
                    let networkData = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
                    countersByName[name] = (rx: UInt64(networkData.ifi_ibytes), tx: UInt64(networkData.ifi_obytes))
                }
            }

            ptr = current.pointee.ifa_next
        }

        let counters = countersByName.map { InterfaceCounters(name: $0.key, rxBytes: $0.value.rx, txBytes: $0.value.tx) }
        return (localIPv4, counters)
    }
}
