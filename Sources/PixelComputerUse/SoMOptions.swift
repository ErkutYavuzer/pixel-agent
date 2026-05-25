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

    public init(
        palette: [SoMColor] = SoMColor.defaultPalette,
        outlineWidth: Double = 4,
        badgeSize: Double = 36,
        fontSize: Double = 20,
        textColor: SoMColor = .white,
        badgePlacement: BadgePlacement = .topLeftInside
    ) {
        // Empty palette guard — caller mantık hatasından korunmak için.
        self.palette = palette.isEmpty ? SoMColor.defaultPalette : palette
        self.outlineWidth = max(0.5, outlineWidth)
        self.badgeSize = max(8, badgeSize)
        self.fontSize = max(6, fontSize)
        self.textColor = textColor
        self.badgePlacement = badgePlacement
    }

    /// Eski hardcoded davranışı korur — v0.2.37'ye kadar SoMRenderer bu değerleri
    /// kullanıyordu.
    public static let `default` = SoMOptions()
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
}
