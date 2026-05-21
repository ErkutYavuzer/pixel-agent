import Foundation

public enum PairingCode {
    public static let length: Int = 6
    public static let alphabet: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  // 0/O, 1/I/L exclude

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
}
