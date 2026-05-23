import Foundation

#if canImport(ApplicationServices)
import ApplicationServices
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Accessibility + Screen Recording izin kontrolü.
///
/// Üç durum:
/// - `hasAccessibility()` → AX query/click/type yapabilir mi?
/// - `hasScreenRecording()` → ScreenCaptureKit kullanabilir mi?
/// - `requestAccessibility(prompt:)` → System Settings'e yönlendirme prompt (false → silent check, true → user-visible dialog).
///
/// Permission state immutable değil — kullanıcı System Settings'te toggle
/// edebilir; her `ui_*` çağrısının başında check edilir.
public enum ComputerUsePermissions {

    // MARK: - Accessibility

    /// AX iznini check eder. Silent — System Settings prompt göstermez.
    public static func hasAccessibility() -> Bool {
        #if canImport(ApplicationServices)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    /// AX iznini check eder; eksikse System Settings prompt'unu açar
    /// (`AXIsProcessTrustedWithOptions(kAXTrustedCheckOptionPrompt: true)`).
    ///
    /// Kullanıcı onayı vermek için manuel olarak Privacy & Security'e gitmek
    /// zorunda — pixel programatik olarak onaylayamaz. İlk açılışta bir kez
    /// çağırmak yeter.
    @discardableResult
    public static func requestAccessibility() -> Bool {
        #if canImport(ApplicationServices)
        // `kAXTrustedCheckOptionPrompt` Apple SDK'sında `extern CFStringRef`
        // (global var) — Swift 6 strict concurrency uyarısı verir. Sabit string
        // değeri direkt kullanılır; AX header'da değişmez.
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options)
        #else
        return false
        #endif
    }

    // MARK: - Screen Recording

    /// Screen Recording iznini check eder. Silent — prompt göstermez.
    ///
    /// `CGPreflightScreenCaptureAccess` macOS 10.15+ var; eksikse `false`
    /// döner. Gerçek capture denemesi yapılınca System Settings prompt'u
    /// otomatik açılır (ScreenCaptureKit ilk kullanımda).
    public static func hasScreenRecording() -> Bool {
        #if canImport(CoreGraphics)
        return CGPreflightScreenCaptureAccess()
        #else
        return false
        #endif
    }

    /// Screen Recording iznini ister (prompt açar). İlk çağrıda kullanıcıya
    /// System Settings dialog'u gösterir; sonraki çağrılar `hasScreenRecording`
    /// ile aynı.
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestScreenCaptureAccess()
        #else
        return false
        #endif
    }

    // MARK: - Combined preflight

    /// Hem AX hem Screen Recording check. Eksik olan ilk hatayı fırlatır.
    public static func preflight() throws {
        guard hasAccessibility() else {
            throw ComputerUseError.accessibilityNotAuthorized
        }
        guard hasScreenRecording() else {
            throw ComputerUseError.screenRecordingNotAuthorized
        }
    }

    /// İzin durumu özet — UI badge veya bridge tool'lar için.
    public struct Status: Sendable, Codable, Equatable {
        public let accessibility: Bool
        public let screenRecording: Bool

        public var allGranted: Bool { accessibility && screenRecording }
    }

    public static func status() -> Status {
        Status(
            accessibility: hasAccessibility(),
            screenRecording: hasScreenRecording()
        )
    }
}
