import PixelCore
import SwiftUI

/// **Sprint 11 (v0.2.36):** Chat message row görsel polish — modern chat
/// pattern'lerine uygun olarak user mesajları sağa hizalı (mavi bubble),
/// assistant solda (mor 0.18 alpha), system ortada (gri). Eski symmetric
/// `HStack { badge; body }` yapısı yerine bubble + alignment.
///
/// Saf helper'lar (Bool/Color/Alignment dönüşümleri); SwiftUI dependency'si
/// sadece tip aliasları için. Test edilebilir.
public enum BubbleAlignment: Sendable, Equatable {
    case leading
    case trailing
    case center

    public static func from(role: MessageRole) -> BubbleAlignment {
        switch role {
        case .user: return .trailing
        case .assistant: return .leading
        case .system: return .center
        }
    }

    /// Row HStack alignment'i: `.leading` → Spacer sağda, `.trailing` →
    /// Spacer solda, `.center` → iki yanda Spacer.
    public var leadingSpacer: Bool {
        self == .trailing || self == .center
    }

    public var trailingSpacer: Bool {
        self == .leading || self == .center
    }
}

public enum BubbleColors {
    /// Bubble arka plan rengi. user dolgu mavi (beyaz text), assistant ve
    /// system yarı saydam (primary text).
    public static func background(for role: MessageRole) -> Color {
        switch role {
        case .user: return Color.blue.opacity(0.85)
        case .assistant: return Color.purple.opacity(0.18)
        case .system: return Color.gray.opacity(0.14)
        }
    }

    /// Text + ikon rengi. user dolgu mavi üzerinde beyaz; diğerleri primary
    /// (system'da italic stilleme View tarafında).
    public static func foreground(for role: MessageRole) -> Color {
        switch role {
        case .user: return .white
        default: return .primary
        }
    }
}

/// Row görsel boyutlama — bubble'ın parent width'e göre max oranı + corner.
public enum BubbleMetrics {
    /// Bubble'ın alabileceği max horizontal ratio. User mesajları daha kısa
    /// (sağa hizalı yatay yer az), assistant uzun cevap yazar (daha geniş).
    public static func maxWidthRatio(for role: MessageRole) -> Double {
        switch role {
        case .user: return 0.75
        case .assistant: return 0.92
        case .system: return 0.7
        }
    }

    public static let cornerRadius: CGFloat = 12
    public static let horizontalPadding: CGFloat = 12
    public static let verticalPadding: CGFloat = 8
}
