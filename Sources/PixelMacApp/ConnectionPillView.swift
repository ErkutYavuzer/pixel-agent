import PixelRemote
import SwiftUI

/// Toolbar'da daimi gözüken eşleşme/bağlantı durum kapsülü (C7).
///
/// Önceki UX: yalnızca `remoteHost.isConnected == true` iken küçük yeşil
/// iPhone ikonu. Eşleşmemiş veya bağlantı kopmuş durum görünmüyordu —
/// kullanıcı her seferinde PairingView sheet'ini açmak zorundaydı.
///
/// Yeni UX: dört state (eşleşmemiş / bağlanıyor / koptu / bağlı) için
/// renkli kapsül; tıklayınca pairing sheet açılır.
struct ConnectionPillView: View {
    let state: ConnectionPillState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: state.systemImage)
                Text(state.label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(state.tint.color)
            .background(
                Capsule()
                    .fill(state.tint.color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(state.tint.color.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(state.helpText)
        .accessibilityLabel(state.label)
    }
}

// MARK: - Pure helper (testable)

/// Bağlantı pill'inin görüntü durumu. `(isPaired, isConnected)` çiftinden
/// türetilir — saf, view'dan bağımsız test edilebilir.
enum ConnectionPillState: Equatable, Sendable {
    /// Henüz pair yapılmamış (`isPaired=false, isConnected=false`).
    case notPaired
    /// Pair handshake yarıda (`isPaired=false, isConnected=true`).
    case connecting
    /// Pair yapıldı ama transport kopuk (`isPaired=true, isConnected=false`).
    case disconnected
    /// Hem pair hem transport canlı (`isPaired=true, isConnected=true`).
    case connected

    static func from(isPaired: Bool, isConnected: Bool) -> ConnectionPillState {
        switch (isPaired, isConnected) {
        case (false, false): return .notPaired
        case (false, true): return .connecting
        case (true, false): return .disconnected
        case (true, true): return .connected
        }
    }

    var label: String {
        switch self {
        case .notPaired: return "Eşleşmemiş"
        case .connecting: return "Bağlanıyor…"
        case .disconnected: return "Bağlantı yok"
        case .connected: return "iPhone bağlı"
        }
    }

    var systemImage: String {
        switch self {
        case .notPaired: return "iphone.slash"
        case .connecting: return "iphone.radiowaves.left.and.right"
        case .disconnected: return "iphone.gen3.slash"
        case .connected: return "iphone.gen3.radiowaves.left.and.right"
        }
    }

    var helpText: String {
        switch self {
        case .notPaired:
            return "iPhone'la eşleşmek için tıkla (QR kod gösterilir)"
        case .connecting:
            return "Pair handshake'i yürütülüyor…"
        case .disconnected:
            return "iPhone eşli ama bağlantı yok — sheet'ten tekrar dene"
        case .connected:
            return "iPhone bağlı — pair detayları için tıkla"
        }
    }

    var tint: ConnectionPillTint {
        switch self {
        case .notPaired: return .gray
        case .connecting: return .yellow
        case .disconnected: return .orange
        case .connected: return .green
        }
    }
}

/// Pill'in renk tonunu temsil eden ham değer — SwiftUI'ya bağımsız test
/// edilebilsin diye Color değil, sembolik. View'da `.color` ile map'lenir.
enum ConnectionPillTint: Equatable, Sendable {
    case gray, yellow, orange, green

    var color: Color {
        switch self {
        case .gray: return .secondary
        case .yellow: return .yellow
        case .orange: return .orange
        case .green: return .green
        }
    }
}
