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
    public static let version = "0.2.24"

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
    ///
    /// **Faz 3b (ADR-0029):** `modifiers` ile cmd/opt/shift/ctrl-click gönderebilir
    /// (örn. `[.command]` = ⌘-click).
    @discardableResult
    public func click(_ q: UIQuery, count: Int = 1, modifiers: ModifierFlags = []) async throws -> UIElement {
        try await ensureAccessibility()
        let elements = try await axBridge.find(q)
        switch elements.count {
        case 0:
            throw ComputerUseError.noMatch(query: q)
        case 1:
            let target = elements[0]
            try await PointerControl.click(at: target.frame.center, count: count, modifiers: modifiers)
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
    ///
    /// **Faz 4 (ADR-0031):** `annotating` dolu ise Set-of-Mark overlay çizilir;
    /// her element için numaralı badge + outline. `ScreenshotResult.marks` 1-bazlı
    /// ID listesi döner. Off-screen element'ler atlanır.
    ///
    /// **Faz 5 (v0.2.38):**
    /// - `autoDiscover: true` ve `annotating` boş ise AX tree'den interactive
    ///   element'ler (button/link/textfield/...) otomatik taranır, annotate
    ///   edilir. Caller önce `ui_query` yazmaktan kurtulur.
    /// - `options` parametresi SoM renderer'ı yapılandırır (palette, outline/
    ///   badge boyutu, content-aware badge placement). `.default` eski hardcoded
    ///   davranış (geri uyumlu).
    public func screenshot(
        of target: ScreenshotTarget = .activeDisplay,
        annotating elements: [UIElement] = [],
        autoDiscover: Bool = false,
        options: SoMOptions = .default
    ) async throws -> ScreenshotResult {
        try await ensureScreenRecording()
        // Faz 5: autoDiscover + annotate boşsa AX'tan tara. annotate dolu ise
        // caller'ın listesi öncelikli (override edilmez — explicit > otomatik).
        var resolvedElements = elements
        if autoDiscover && resolvedElements.isEmpty {
            try await ensureAccessibility()
            let discoverBundle: String? = {
                if case .window(let bid) = target { return bid }
                if case .windowContent(let bid, _) = target { return bid }
                return nil  // .activeDisplay / .allDisplays → frontmost app
            }()
            resolvedElements = try await axBridge.discoverInteractive(bundleID: discoverBundle)
        }
        return try await ScreenshotCapture.capture(
            target: target,
            annotating: resolvedElements,
            options: options
        )
    }

    /// **Faz 3a:** Daha önce `query()` ile alınmış bir `opaqueID`'den canlı
    /// element snapshot'ı üretir. Element artık yoksa (UI değişmiş, app kapanmış,
    /// vs.) `nil` döner. Cache yok — her resolve fresh path-walk yapar.
    ///
    /// Tipik kullanım: query → ekran/UI değişimi → re-resolve → click.
    public func resolve(opaqueID: String) async throws -> UIElement? {
        try await ensureAccessibility()
        return try await axBridge.resolve(opaqueID: opaqueID)
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
