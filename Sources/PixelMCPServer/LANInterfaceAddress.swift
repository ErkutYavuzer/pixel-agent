import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// en0/en1 üzerindeki primary IPv4 LAN adresini tespit eder. PixelMacApp içindeki
/// `detectLANIPv4()` ile aynı mantık — gelecekte ortak modüle (PixelCore?) taşınabilir.
public enum LANInterfaceAddress {
    public static func primary() -> String? {
        #if canImport(Darwin)
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let interface = current.pointee
            guard let addr = interface.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                addr, socklen_t(addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            )
            let ip = String(cString: hostname)
            if !ip.isEmpty, ip != "127.0.0.1" {
                address = ip
                break
            }
        }
        return address
        #else
        return nil
        #endif
    }
}
