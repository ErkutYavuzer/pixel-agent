import SwiftUI

/// `ChatComposer`'ın TextField'ı etrafındaki overlay halo'sunun stili (A8).
///
/// Üç state — none / plan / focused — birbiriyle çakışabilir; öncelik:
/// `streaming → none` (disabled görseli zaten anlatıyor); aksi halde
/// `plan > focused > none`. Saf — `@FocusState` ve view'dan ayrı test
/// edilebilir.
enum ComposerHaloStyle: Equatable, Sendable {
    case none
    /// Plan Mode aktif — turuncu kenarlık (mevcut görsel sözleşme).
    case plan
    /// TextField aktif fokusta ama Plan Mode kapalı — mor halo.
    case focused

    static func resolve(planMode: Bool, isFocused: Bool, isStreaming: Bool) -> ComposerHaloStyle {
        if isStreaming { return .none }
        if planMode { return .plan }
        if isFocused { return .focused }
        return .none
    }

    /// View-side renk eşlemesi. Helper saf kalsın diye `Color` burada.
    var strokeColor: Color {
        switch self {
        case .none: return .clear
        case .plan: return .orange.opacity(0.55)
        case .focused: return .purple.opacity(0.45)
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .none: return 0
        case .plan, .focused: return 1.5
        }
    }

    var isVisible: Bool {
        self != .none
    }
}
