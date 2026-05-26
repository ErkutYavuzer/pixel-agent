import Darwin
import Foundation

/// **Sprint 47 (v0.2.75):** Relay URL fallback chain — kullanıcı kararı
/// hiyerarşik olarak çözümlenir.
///
/// **Karar zinciri (öncelik sırası):**
/// 1. **UserDefaults override** (`pixel.relay.customURL`) — Settings'ten
///    kullanıcı manuel set ettiyse en öncelikli.
/// 2. **`PIXEL_RELAY_URL` environment variable** — eski Sprint 6.1
///    pattern, geriye uyumluluk.
/// 3. **Production Cloudflare Worker URL** — `wrangler deploy` ile
///    yayınlanan public URL. Sprint 47 default `nil` (kullanıcı henüz
///    deploy etmedi); deploy edilirse hardcoded ekle.
/// 4. **LAN IP** — `en0`/`en1` ile auto-detect; lokal `wrangler dev` ile
///    aynı network'ten iPhone bağlanabilir.
/// 5. **localhost** — son fallback (sadece Mac kendi test'i için).
///
/// **Saf helper** — `Sendable`. Test edilebilir (UserDefaults + env inject).
public enum RelayURLResolver: Sendable {
    public static let customURLDefaultsKey = "pixel.relay.customURL"
    public static let envVarName = "PIXEL_RELAY_URL"

    /// **Sprint 47:** Production Cloudflare URL — `wrangler deploy` sonrası
    /// hardcoded. Şu an `nil` (kullanıcı kendi deploy etmeli).
    public static let productionURL: String? = nil

    /// **Sprint 47:** Resolve order ile relay URL döndür.
    /// `defaults` ve `environment` test edilebilirlik için inject edilir.
    public static func resolve(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        // 1. UserDefaults
        if let custom = defaults.string(forKey: customURLDefaultsKey),
           !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }
        // 2. ENV var
        if let env = environment[envVarName],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env
        }
        // 3. Production URL (deploy sonrası)
        if let prod = productionURL {
            return prod
        }
        // 4. LAN IP
        if let lan = detectLANIPv4() {
            return "ws://\(lan):8787"
        }
        // 5. localhost fallback
        return "ws://localhost:8787"
    }

    /// **Sprint 47:** Resolution kaynağını döndür — Settings UI'da kullanıcıya
    /// göstermek için ("Custom" / "Env" / "Production" / "LAN" / "localhost").
    public static func resolveSource(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Source {
        if let custom = defaults.string(forKey: customURLDefaultsKey),
           !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return .custom(custom)
        }
        if let env = environment[envVarName],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return .environment(env)
        }
        if let prod = productionURL {
            return .production(prod)
        }
        if let lan = detectLANIPv4() {
            return .lan(ip: lan)
        }
        return .localhost
    }

    /// **Sprint 47:** Custom URL kaydet veya temizle (nil → custom override sil).
    public static func setCustomURL(_ url: String?, defaults: UserDefaults = .standard) {
        if let url, !url.trimmingCharacters(in: .whitespaces).isEmpty {
            defaults.set(url, forKey: customURLDefaultsKey)
        } else {
            defaults.removeObject(forKey: customURLDefaultsKey)
        }
    }

    /// **Sprint 47:** `en0`/`en1` LAN IPv4 detect. PixelMacApp'tan taşındı
    /// (Sprint 6.1'den beri aynı kod) — burada saf helper olarak test edilebilir.
    public static func detectLANIPv4() -> String? {
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
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            let ip = String(cString: hostname)
            if !ip.isEmpty, ip != "127.0.0.1" {
                address = ip
                break
            }
        }
        return address
    }

    /// **Sprint 47:** Resolution kaynağı — UI display + test introspection.
    public enum Source: Sendable, Equatable {
        case custom(String)
        case environment(String)
        case production(String)
        case lan(ip: String)
        case localhost

        public var url: String {
            switch self {
            case .custom(let u), .environment(let u), .production(let u): return u
            case .lan(let ip): return "ws://\(ip):8787"
            case .localhost: return "ws://localhost:8787"
            }
        }

        public var displayName: String {
            switch self {
            case .custom: return "Özel"
            case .environment: return "PIXEL_RELAY_URL"
            case .production: return "Cloudflare"
            case .lan: return "LAN"
            case .localhost: return "localhost"
            }
        }
    }
}
