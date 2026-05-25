import PixelCore
import SwiftUI

/// **Sprint 12 (v0.2.37):** iOS chat row görsel polish — Mac'in v0.2.36
/// `BubbleStyle.swift`'inin iOS paraleli. Hardcoded color/shape değerleri
/// burada konsolide edildi; saf helper'lar test edilebilir + Mac ile
/// görsel kontrat hizalı.
///
/// **Not:** iOS'ta `Message.role` zaten asymmetric layout kullanıyordu (Mac
/// v0.2.36'da yetişti). Bu refactor görsel davranışı değiştirmez —
/// maintainability + cross-platform consistency için extraction.
enum IOSBubbleAlignment: Sendable, Equatable {
    case leading      // assistant
    case trailing     // user
    case center       // system

    static func from(role: MessageRole) -> IOSBubbleAlignment {
        switch role {
        case .user: return .trailing
        case .assistant: return .leading
        case .system: return .center
        }
    }
}

enum IOSBubbleColors {
    /// Background — Mac BubbleColors paralel ama iOS sistem renkleri tercih
    /// (semantik adaptive: light/dark mode).
    static func background(for role: MessageRole) -> Color {
        switch role {
        case .user: return .blue
        case .assistant: return Color(.secondarySystemGroupedBackground)
        case .system: return .clear
        }
    }

    static func foreground(for role: MessageRole) -> Color {
        switch role {
        case .user: return .white
        case .assistant: return .primary
        case .system: return .secondary
        }
    }

    /// Shadow — user mavi gölge, assistant nötr soft. System'da gölge yok.
    static func shadowColor(for role: MessageRole) -> Color {
        switch role {
        case .user: return .blue.opacity(0.15)
        case .assistant: return .black.opacity(0.04)
        case .system: return .clear
        }
    }

    static func shadowRadius(for role: MessageRole) -> CGFloat {
        switch role {
        case .user: return 3
        case .assistant: return 2
        case .system: return 0
        }
    }
}

enum IOSBubbleMetrics {
    static let cornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
}
