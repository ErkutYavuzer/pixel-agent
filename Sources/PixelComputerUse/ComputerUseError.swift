import Foundation

/// PixelComputerUse hataları. MCP tool error'larına çevrilmek üzere
/// `LocalizedError.errorDescription` kullanıcıya gösterilecek metni döner.
public enum ComputerUseError: Error, LocalizedError, Sendable {
    /// `AXIsProcessTrustedWithOptions` false — System Settings → Privacy & Security
    /// → Accessibility'den PixelAgent.app onaylanmalı.
    case accessibilityNotAuthorized

    /// `CGPreflightScreenCaptureAccess` veya `SCShareableContent.current`
    /// permission denied — Screen Recording onayı eksik.
    case screenRecordingNotAuthorized

    /// Query hiçbir element eşleştirmedi.
    case noMatch(query: UIQuery)

    /// Query'e birden fazla element eşleşti — caller refine etmeli (örn.
    /// bundleID + identifier ekle).
    case ambiguousMatch(query: UIQuery, count: Int)

    /// AX/CGEvent çağrısı zaman aşımına uğradı.
    case timedOut(after: TimeInterval)

    /// Bu platformda desteklenmiyor (örn. iOS no-op stub).
    case unsupported(reason: String)

    /// ApplicationServices AX C API hata kodu döndü.
    case axCallFailed(code: Int32, hint: String)

    /// ScreenCaptureKit pipeline'ı başarısız.
    case screenshotFailed(reason: String)

    /// CGEvent enjeksiyonu başarısız.
    case eventInjectionFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotAuthorized:
            return "Accessibility izni yok — System Settings → Privacy & Security → Accessibility'den PixelAgent'ı onayla."
        case .screenRecordingNotAuthorized:
            return "Screen Recording izni yok — System Settings → Privacy & Security → Screen Recording'den PixelAgent'ı onayla."
        case .noMatch(let q):
            return "UI element bulunamadı: \(q.debugSummary)"
        case .ambiguousMatch(let q, let n):
            return "Belirsiz eşleşme: \(n) element uydu — query'yi daralt (\(q.debugSummary))"
        case .timedOut(let t):
            return "Zaman aşımı (\(String(format: "%.1f", t))s)"
        case .unsupported(let reason):
            return "Desteklenmiyor: \(reason)"
        case .axCallFailed(let code, let hint):
            return "AX çağrısı başarısız (code=\(code)): \(hint)"
        case .screenshotFailed(let reason):
            return "Ekran görüntüsü alınamadı: \(reason)"
        case .eventInjectionFailed(let reason):
            return "Olay enjeksiyonu başarısız: \(reason)"
        }
    }
}
