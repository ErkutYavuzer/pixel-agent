import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// **Faz 5 (v0.2.38):** Set-of-Mark renderer için override edilebilir
/// görselleştirme parametreleri. v0.2.31'e kadar palette/outline/badge
/// sabitti; şimdi tüm bunlar yapılandırılabilir.
///
/// Saf data, Codable + Sendable + Equatable — wire'da MCP şemasından
/// gelir, test'lerden direkt instantiable.
///
/// `.default` eski hardcoded davranışı korur (geri uyumlu).
public struct SoMOptions: Sendable, Equatable, Codable {
    /// Element outline'ı için renk paleti. N element → `i % palette.count` döner.
    /// Boş palette validate aşamasında reject edilir (`SoMOptions.init` throws).
    public let palette: [SoMColor]
    /// Outline çizgi kalınlığı (pixel). Tipik retina capture'da 4pt iyi.
    public let outlineWidth: Double
    /// Numbered badge'in çapı (pixel). Default 36pt.
    public let badgeSize: Double
    /// Badge text font size (pixel). Default 20pt.
    public let fontSize: Double
    /// Badge text rengi. Default beyaz (palette renkleri üzerine kontrast).
    public let textColor: SoMColor
    /// Badge'in element'e göre yerleşim stratejisi.
    public let badgePlacement: BadgePlacement
    /// **Faz 5c follow-up (v0.2.52):** `.contentAware` placement için OCR
    /// crop modu. Sadece `badgePlacement == .contentAware` iken anlamlı —
    /// diğer modlarda yoksayılır.
    public let ocrCropMode: OCRCropMode
    /// **Faz 5c follow-up (v0.2.54):** Vision OCR'da minimum text confidence
    /// threshold (0.0-1.0). Bu değerin altındaki text observations filtre
    /// edilir. Default 0.0 — tümü kabul edilir (Sprint 26 davranışı, backward
    /// compat). 0.5 ortalama bir filtre; 0.8 sıkı (sadece kesin text).
    /// `.fast` recognition level low-confidence noise üretebildiği için
    /// yükseltmek scoring quality'sini artırır.
    public let ocrMinConfidence: Double

    public init(
        palette: [SoMColor] = SoMColor.defaultPalette,
        outlineWidth: Double = 4,
        badgeSize: Double = 36,
        fontSize: Double = 20,
        textColor: SoMColor = .white,
        badgePlacement: BadgePlacement = .topLeftInside,
        ocrCropMode: OCRCropMode = .wholeImage,
        ocrMinConfidence: Double = 0.0
    ) {
        // Empty palette guard — caller mantık hatasından korunmak için.
        self.palette = palette.isEmpty ? SoMColor.defaultPalette : palette
        self.outlineWidth = max(0.5, outlineWidth)
        self.badgeSize = max(8, badgeSize)
        self.fontSize = max(6, fontSize)
        self.textColor = textColor
        self.badgePlacement = badgePlacement
        self.ocrCropMode = ocrCropMode
        self.ocrMinConfidence = min(1.0, max(0.0, ocrMinConfidence))
    }

    // MARK: - Codable (manuel) — yeni field'lar eski JSON'da yoksa default'a
    // düşer. Sprint 26+ wire format'ı bozulmaz.

    private enum CodingKeys: String, CodingKey {
        case palette, outlineWidth, badgeSize, fontSize, textColor,
             badgePlacement, ocrCropMode, ocrMinConfidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let palette = try c.decodeIfPresent([SoMColor].self, forKey: .palette)
            ?? SoMColor.defaultPalette
        let outlineWidth = try c.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? 4
        let badgeSize = try c.decodeIfPresent(Double.self, forKey: .badgeSize) ?? 36
        let fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 20
        let textColor = try c.decodeIfPresent(SoMColor.self, forKey: .textColor) ?? .white
        let badgePlacement = try c.decodeIfPresent(BadgePlacement.self, forKey: .badgePlacement)
            ?? .topLeftInside
        let ocrCropMode = try c.decodeIfPresent(OCRCropMode.self, forKey: .ocrCropMode)
            ?? .wholeImage
        let ocrMinConfidence = try c.decodeIfPresent(Double.self, forKey: .ocrMinConfidence)
            ?? 0.0
        self.init(
            palette: palette,
            outlineWidth: outlineWidth,
            badgeSize: badgeSize,
            fontSize: fontSize,
            textColor: textColor,
            badgePlacement: badgePlacement,
            ocrCropMode: ocrCropMode,
            ocrMinConfidence: ocrMinConfidence
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(palette, forKey: .palette)
        try c.encode(outlineWidth, forKey: .outlineWidth)
        try c.encode(badgeSize, forKey: .badgeSize)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(textColor, forKey: .textColor)
        try c.encode(badgePlacement, forKey: .badgePlacement)
        try c.encode(ocrCropMode, forKey: .ocrCropMode)
        try c.encode(ocrMinConfidence, forKey: .ocrMinConfidence)
    }

    /// Eski hardcoded davranışı korur — v0.2.37'ye kadar SoMRenderer bu değerleri
    /// kullanıyordu.
    public static let `default` = SoMOptions()
}

/// **Faz 5c follow-up (v0.2.52):** OCR pass scope strategy'si.
///
/// - `.wholeImage` (default): Tek Vision pass tüm screenshot üzerinde — N
///   element için 1 pass. Vision overhead amortize olur; çok element varsa
///   wall-clock daha hızlı (~100-300ms typical retina).
/// - `.perElement`: Her element için ayrı Vision pass üzerinde
///   `ElementRegionExpander.expandedRect` crop'u. Element başına ~50-150ms,
///   N pass = N × overhead. Az element (1-3) ve element'ler çok küçükse
///   wall-clock daha hızlı; ayrıca scoring scope'ı element neighborhood'una
///   sınırlı (uzak text'in noise'u yok). Çoğunluk case için `.wholeImage`
///   daha iyi; `.perElement` özel layout senaryoları için opt-in.
///
/// **Wire format:** Raw value explicit snake_case (MCP convention) — Swift
/// property camelCase, wire string snake_case. `BadgePlacement` raw'ı
/// camelCase (Sprint 26 ile shipped); yeni enum'larda snake_case raw value
/// MCP doc'lar ile tutarlı olmaya başlıyor.
public enum OCRCropMode: String, Sendable, Equatable, Codable {
    case wholeImage = "whole_image"
    case perElement = "per_element"
}

/// RGBA renk — `CGColor`'ı doğrudan Codable yapmak zor olduğu için saf struct.
public struct SoMColor: Sendable, Equatable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = SoMColor(red: 1, green: 1, blue: 1, alpha: 1)
    public static let black = SoMColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// v0.2.31'e kadar SoMRenderer'ın hardcoded 5 rengi.
    public static let defaultPalette: [SoMColor] = [
        SoMColor(red: 1.00, green: 0.20, blue: 0.20, alpha: 0.90),  // kırmızı
        SoMColor(red: 0.20, green: 0.60, blue: 1.00, alpha: 0.90),  // mavi
        SoMColor(red: 0.20, green: 0.80, blue: 0.30, alpha: 0.90),  // yeşil
        SoMColor(red: 1.00, green: 0.70, blue: 0.00, alpha: 0.90),  // turuncu
        SoMColor(red: 0.85, green: 0.30, blue: 0.95, alpha: 0.90),  // mor
    ]

    #if canImport(CoreGraphics)
    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    #endif
}

/// Badge'in element rect'ine göre yerleşim stratejisi.
public enum BadgePlacement: String, Sendable, Equatable, Codable {
    /// Element rect'in sol-üst köşesi içinde (v0.2.37 davranışı — geri uyumlu).
    case topLeftInside
    /// Element rect'in sol-üst köşesi dışında (yukarı + sol, element içeriği
    /// kapanmaz). Çok küçük element'ler için iyi.
    case topLeftOutside
    /// Element rect'in sağ-üst köşesi içinde.
    case topRightInside
    /// Element rect'in sağ-üst köşesi dışında.
    case topRightOutside
    /// Image bounds'a göre en uygun köşeyi otomatik seç (image kenarına
    /// yakın değilse `.topLeftOutside` tercih — content kapanmasın; aksi
    /// halde içeri kayar).
    case smartCorner
    /// **Faz 5b (v0.2.45):** AX element role'üne göre içerik-aware konum.
    /// Button text merkezde → köşe; link text sol kenar → sağ-üst; checkbox
    /// simgesi sol + label sağ → sağ-üst dış. `LabelAwarePlacementResolver`
    /// her element için role'den concrete placement türetir; sonra image
    /// bounds clamping mevcut pattern.
    case labelAware
    /// **Faz 5c (v0.2.51):** OCR-based content-aware konum. `Vision` framework
    /// ile screenshot'taki tüm text bounding box'ları çıkarılır, her element
    /// için 4 köşe adayı arasından **text ile en az çakışan** seçilir. AX
    /// heuristic'in pratik limiti aşıldığında (özel layout'lar, custom
    /// widget'lar) badge gerçek metin alanlarını örtmez. `ScreenshotCapture`
    /// upfront OCR çağırır; SoMRenderer detected text regions ile çalışır.
    /// OCR başarısız veya text yoksa `.labelAware` fallback.
    case contentAware
}
