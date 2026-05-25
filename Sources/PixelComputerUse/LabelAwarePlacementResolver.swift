import Foundation

/// **Faz 5b (v0.2.45):** AX element role'üne göre badge placement seç.
/// `BadgePlacement.labelAware` strategy'sinin kalbi — caller per-element
/// concrete bir placement (topLeftInside/Outside/topRightInside/Outside)
/// alır, sonra `BadgeLayout.computeBadgeRect` ile geometry hesabı.
///
/// **Heuristic:**
/// - **AXButton / AXMenuItem / AXCheckBox / AXRadioButton** → `topRightOutside`
///   Button text genelde merkezde veya soldan padding'li; sağ-üst dış köşe
///   en az çakışır. Checkbox/radio simgesi sol kenarda + label sağda →
///   dış köşe badge text üstüne çakışmaz.
/// - **AXLink / AXTextField / AXTextArea / AXPopUpButton / AXComboBox** →
///   `topRightInside` Link text sol kenarda (browser convention); textField
///   placeholder sol-orta; popup/combo dropdown ok sağda küçük → sağ-üst
///   içeride min text overlap.
/// - **Diğer rol (AXImage, AXGroup, vs.)** → `topLeftOutside` Sınırlı
///   semantik bilgi → smartCorner pattern fallback (üstüne taşan badge
///   genelde minimum content kapatır).
///
/// Saf helper — AX bağımsız, sadece role string'i alır. Test edilebilir.
public enum LabelAwarePlacementResolver {

    public static func placement(for role: String) -> BadgePlacement {
        switch role {
        case "AXButton",
             "AXMenuItem",
             "AXCheckBox",
             "AXRadioButton":
            return .topRightOutside

        case "AXLink",
             "AXTextField",
             "AXTextArea",
             "AXPopUpButton",
             "AXComboBox":
            return .topRightInside

        default:
            // Sınırlı semantik bilgi — smartCorner pattern fallback
            // (image bounds'a göre BadgeLayout zaten ek clamp yapar).
            return .topLeftOutside
        }
    }
}
