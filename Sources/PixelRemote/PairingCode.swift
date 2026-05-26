import Foundation

public enum PairingCode {
    public static let length: Int = 6
    public static let alphabet: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  // 0/O, 1/I/L exclude

    /// **Sprint 34 (v0.2.61):** UserDefaults key — Mac launch'lar arası
    /// pairingCode persist edilir. iOS saved pairing aynı kodu beklediği için
    /// her Mac restart yeni kod üretmek = iOS bağlanamaz UX bug.
    public static let storedCodeKey = "pixel-agent.mac.pairingCode"

    public static func generate() -> String {
        var code = ""
        let alphabet = Array(Self.alphabet)
        for _ in 0..<length {
            let index = Int.random(in: 0..<alphabet.count)
            code.append(alphabet[index])
        }
        return code
    }

    public static func isValid(_ code: String) -> Bool {
        guard code.count == length else { return false }
        let allowed = Set(alphabet)
        return code.allSatisfy { allowed.contains($0) }
    }

    /// **Sprint 34 (v0.2.61):** UserDefaults'tan saved code'u yükle; yoksa
    /// yeni üret + save. Mac launch'lar arası code aynı kalır → iOS saved
    /// pairing auto-reconnect çalışır.
    public static func loadOrGenerate(
        userDefaults: UserDefaults = .standard
    ) -> String {
        if let saved = userDefaults.string(forKey: storedCodeKey),
           isValid(saved) {
            return saved
        }
        let fresh = generate()
        userDefaults.set(fresh, forKey: storedCodeKey)
        return fresh
    }

    /// **Sprint 34 (v0.2.61):** Pairing code persist — `regenerateCode()`
    /// veya init'te yeni üretildiğinde çağrılır.
    public static func save(
        _ code: String,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(code, forKey: storedCodeKey)
    }
}
