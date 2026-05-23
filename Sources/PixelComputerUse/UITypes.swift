import CoreGraphics
import Foundation

// MARK: - UIQuery

/// UI element araması için filtre. Tüm alanlar opsiyonel — set edilenler AND
/// mantığıyla birleşir.
///
/// MCP üzerinden JSON olarak alınır (Codable). In-process'te de aynı API.
public struct UIQuery: Sendable, Codable, Equatable, Hashable {
    /// Hedef uygulamanın bundle ID'si (örn. "com.apple.Safari"). nil → tüm
    /// frontmost-olmayan uygulamalar da taranır (yavaş; üretimde set et).
    public var bundleID: String?

    /// AX role filtresi (örn. `.button`, `.textField`). nil → tüm rol'ler.
    public var role: AXRole?

    /// Element title (AXTitle) match'i. matchMode'a göre exact/fuzzy/regex.
    public var title: String?

    /// AXDescription veya AXLabel match'i.
    public var label: String?

    /// AXIdentifier — Accessibility Inspector'da görünen kararlı tanımlayıcı.
    /// En güvenilir match; varsa diğer alanları override eder.
    public var identifier: String?

    /// **Faz 3a:** title VEYA label'a karşı **case-insensitive substring** match.
    /// `title` ve `label` alanlarından bağımsız çalışır (parallel constraint).
    /// Caller "Sign In" yazarsa hem `title="Sign In"` hem `label="Sign In Button"`
    /// element'ini bulur. `matchMode`'a tabi değil — her zaman `caseInsensitive`
    /// contains.
    public var containsText: String?

    /// **Faz 3a:** Element'in herhangi bir ancestor'unun bu query'lerden HER BİRİNE
    /// uyması gerekir. Dizi boş = constraint yok. Birden fazla constraint = AND
    /// (her biri farklı veya aynı ancestor'a uyabilir).
    ///
    /// Örnek: "Sidebar grubu içindeki Save butonu"
    /// ```swift
    /// UIQuery(role: .button, title: "Save",
    ///         within: [UIQuery(role: .group, title: "Sidebar")])
    /// ```
    ///
    /// Recursive — `within` içindeki UIQuery'lerin de kendi `within` constraint'i
    /// olabilir (root'a kadar zincir).
    public var within: [UIQuery]

    /// Match stratejisi. Default: `.exact`.
    public var matchMode: MatchMode

    /// Tree traversal max derinlik. Default: 12. Daha yüksek = yavaş.
    public var maxDepth: Int

    /// Genel timeout (saniye). Default: 3.0.
    public var timeout: TimeInterval

    public init(
        bundleID: String? = nil,
        role: AXRole? = nil,
        title: String? = nil,
        label: String? = nil,
        identifier: String? = nil,
        containsText: String? = nil,
        within: [UIQuery] = [],
        matchMode: MatchMode = .exact,
        maxDepth: Int = 12,
        timeout: TimeInterval = 3.0
    ) {
        self.bundleID = bundleID
        self.role = role
        self.title = title
        self.label = label
        self.identifier = identifier
        self.containsText = containsText
        self.within = within
        self.matchMode = matchMode
        self.maxDepth = maxDepth
        self.timeout = timeout
    }

    /// Logging/error display için kısa özet.
    public var debugSummary: String {
        var parts: [String] = []
        if let b = bundleID { parts.append("bundle=\(b)") }
        if let r = role { parts.append("role=\(r.rawValue)") }
        if let t = title { parts.append("title=\"\(t)\"") }
        if let l = label { parts.append("label=\"\(l)\"") }
        if let i = identifier { parts.append("id=\(i)") }
        if let c = containsText { parts.append("contains=\"\(c)\"") }
        if matchMode != .exact { parts.append("mode=\(matchMode.rawValue)") }
        if !within.isEmpty { parts.append("within=[\(within.count)]") }
        return parts.isEmpty ? "(boş)" : parts.joined(separator: " ")
    }

    // MARK: - Codable

    /// `within` ve `containsText` Faz 3a'da eklendi; v0.2.12 ve öncesi JSON'lar
    /// bu alanlar olmadan gelir. `decodeIfPresent` ile geriye uyumlu.
    private enum CodingKeys: String, CodingKey {
        case bundleID, role, title, label, identifier
        case containsText, within
        case matchMode, maxDepth, timeout
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        self.role = try c.decodeIfPresent(AXRole.self, forKey: .role)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
        self.containsText = try c.decodeIfPresent(String.self, forKey: .containsText)
        self.within = try c.decodeIfPresent([UIQuery].self, forKey: .within) ?? []
        self.matchMode = try c.decodeIfPresent(MatchMode.self, forKey: .matchMode) ?? .exact
        self.maxDepth = try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 12
        self.timeout = try c.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 3.0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(bundleID, forKey: .bundleID)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(identifier, forKey: .identifier)
        try c.encodeIfPresent(containsText, forKey: .containsText)
        if !within.isEmpty { try c.encode(within, forKey: .within) }
        try c.encode(matchMode, forKey: .matchMode)
        try c.encode(maxDepth, forKey: .maxDepth)
        try c.encode(timeout, forKey: .timeout)
    }
}

// MARK: - AXRole

/// macOS AX rol sabitleri. AX API string-bazlı; bu enum kullanıcı-dostu
/// shorthand sunar. `*` her rolü kabul eder.
public enum AXRole: String, Sendable, Codable, CaseIterable {
    case button = "AXButton"
    case textField = "AXTextField"
    case textArea = "AXTextArea"
    case staticText = "AXStaticText"
    case menuItem = "AXMenuItem"
    case menu = "AXMenu"
    case menuBar = "AXMenuBar"
    case checkbox = "AXCheckBox"
    case radioButton = "AXRadioButton"
    case popUpButton = "AXPopUpButton"
    case comboBox = "AXComboBox"
    case link = "AXLink"
    case image = "AXImage"
    case group = "AXGroup"
    case window = "AXWindow"
    case toolbar = "AXToolbar"
    case tabGroup = "AXTabGroup"
    case scrollArea = "AXScrollArea"
    case any = "*"
}

// MARK: - MatchMode

public enum MatchMode: String, Sendable, Codable {
    /// Tam eşleşme (case-sensitive).
    case exact
    /// `contains` (case-insensitive). Fuzzy değil — gerçek fuzzy Faz 2.
    case fuzzy
    /// NSRegularExpression. Yanlış pattern → `axCallFailed`.
    case regex
}

// MARK: - UIElement

/// Bulunan UI element'in value-type snapshot'ı. AX referansı (AXUIElement)
/// burada **tutulmaz** — bu yapıyı actor sınırları arası geçirmek güvenli.
///
/// Re-resolve gerekiyorsa (örn. element konum değiştiyse) caller `query()`
/// tekrar çağırır. Faz 2'de `opaqueID` ile cache-backed re-resolve eklenir.
public struct UIElement: Sendable, Codable, Equatable, Hashable {
    public let role: String
    public let title: String?
    public let label: String?
    public let identifier: String?
    public let frame: CGRectBox
    public let bundleID: String?
    /// Root'tan element'e role chain (örn. ["AXWindow", "AXToolbar", "AXButton"]).
    public let path: [String]
    /// Re-resolve için kullanılabilecek deterministic key (Faz 2). Faz 1'de
    /// `path.joined("/") + identifier/title`.
    public let opaqueID: String

    public init(
        role: String,
        title: String?,
        label: String?,
        identifier: String?,
        frame: CGRectBox,
        bundleID: String?,
        path: [String],
        opaqueID: String
    ) {
        self.role = role
        self.title = title
        self.label = label
        self.identifier = identifier
        self.frame = frame
        self.bundleID = bundleID
        self.path = path
        self.opaqueID = opaqueID
    }
}

// MARK: - CGRectBox

/// `CGRect`'i Codable yapan adapter — Foundation `CGRect` doğrudan Codable
/// değil (bazı SDK versiyonlarında), bu kütüphane'de Sendable+Codable ihtiyacı
/// için sarılır.
public struct CGRectBox: Sendable, Codable, Equatable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }

    public static let zero = CGRectBox(x: 0, y: 0, width: 0, height: 0)
}

// MARK: - Screenshot

/// Ekran görüntüsü hedefi.
public enum ScreenshotTarget: Sendable, Codable, Equatable {
    /// Tüm displayler birleşik (rare).
    case allDisplays
    /// Frontmost app'ın bulunduğu display (default).
    case activeDisplay
    /// Belirli bundleID'li uygulamanın frontmost penceresi.
    case window(bundleID: String)
}

/// Capture sonucu. `pngData` PNG-encoded; MCP üzerinden base64'lenir.
public struct ScreenshotResult: Sendable, Codable, Equatable {
    public let pngData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let logicalFrame: CGRectBox
    public let bundleID: String?
    public let capturedAt: Date

    public init(
        pngData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        logicalFrame: CGRectBox,
        bundleID: String?,
        capturedAt: Date = Date()
    ) {
        self.pngData = pngData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.logicalFrame = logicalFrame
        self.bundleID = bundleID
        self.capturedAt = capturedAt
    }
}
