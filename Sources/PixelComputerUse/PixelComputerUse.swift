import Foundation

/// PixelComputerUse — pixel-agent'ın AX-first hybrid desktop control katmanı.
///
/// Mimari: 3 katman — Algı (AX + Screenshot), Kontrol (CGEvent), Karar dışarıda (LLM).
///
/// Kullanım:
/// ```swift
/// let computer = PixelComputerUse()
/// let q = UIQuery(role: .button, title: "Sign In", matchMode: .exact)
/// let element = try await computer.click(q)
/// ```
///
/// Permission: ilk `ui_*` çağrısından önce `ComputerUsePermissions.preflight(...)`
/// çağrılır; eksik izin `ComputerUseError.accessibilityNotAuthorized` veya
/// `.screenRecordingNotAuthorized` fırlatır.
///
/// İlgili ADR: [`docs/adr/0026-pixel-computer-use.md`](../../../docs/adr/0026-pixel-computer-use.md)
public actor PixelComputerUse {
    public static let version = "0.1.0"

    /// Permission preflight stratejisi (test için DI).
    public enum PermissionPolicy: Sendable {
        /// Üretim: gerçek `AXIsProcessTrustedWithOptions` + `SCShareableContent`.
        case live
        /// Test: tüm izinler "verilmiş" sayılır. UI side-effect'siz mock'lar için.
        case bypass
    }

    private let policy: PermissionPolicy
    private let axBridge: AXBridge

    public init(policy: PermissionPolicy = .live) {
        self.policy = policy
        self.axBridge = AXBridge()
    }

    // MARK: - Public API

    /// UI ağacında query'ye uyan element'leri döndürür. Match yoksa boş dizi
    /// (`throw` etmez — caller `noMatch` semantiğini tool seviyesinde uygular).
    public func query(_ q: UIQuery) async throws -> [UIElement] {
        try await ensureAccessibility()
        return try await axBridge.find(q)
    }

    /// Query'ye uyan tek element'i tıklar. 0 match → `.noMatch`; ≥2 match →
    /// `.ambiguousMatch`; tıklama başarısızlığı → `.axCallFailed`.
    @discardableResult
    public func click(_ q: UIQuery, count: Int = 1) async throws -> UIElement {
        try await ensureAccessibility()
        let elements = try await axBridge.find(q)
        switch elements.count {
        case 0:
            throw ComputerUseError.noMatch(query: q)
        case 1:
            let target = elements[0]
            try await PointerControl.click(at: target.frame.center, count: count)
            return target
        default:
            throw ComputerUseError.ambiguousMatch(query: q, count: elements.count)
        }
    }

    /// Aktif text input element'ine veya `into` ile belirlenen hedefe metin yazar.
    /// Önce focus (tıklama), sonra her karakter için `CGEventCreateKeyboardEvent`.
    public func type(_ text: String, into q: UIQuery? = nil) async throws {
        try await ensureAccessibility()
        if let q {
            _ = try await click(q, count: 1)  // focus için tek tıkla
        }
        try await PointerControl.typeText(text)
    }

    /// Ekran görüntüsü alır. Hedef: tüm ekran, aktif display, veya bundleID'li
    /// uygulamanın penceresi.
    public func screenshot(of target: ScreenshotTarget = .activeDisplay) async throws -> ScreenshotResult {
        try await ensureScreenRecording()
        return try await ScreenshotCapture.capture(target: target)
    }

    // MARK: - Permission preflight

    private func ensureAccessibility() async throws {
        guard policy == .live else { return }
        guard ComputerUsePermissions.hasAccessibility() else {
            throw ComputerUseError.accessibilityNotAuthorized
        }
    }

    private func ensureScreenRecording() async throws {
        guard policy == .live else { return }
        guard ComputerUsePermissions.hasScreenRecording() else {
            throw ComputerUseError.screenRecordingNotAuthorized
        }
    }
}
