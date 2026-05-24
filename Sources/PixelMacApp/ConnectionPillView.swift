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
    /// **Sprint 4 (connection-lost pulse):** Caller bunu yeni bir Date'e set
    /// edince ripple animasyonu tetiklenir (scale 1→1.7 + opacity 0.8→0).
    /// nil veya değişmemiş Date → animasyon yok.
    var pulseTrigger: Date? = nil
    let onTap: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0

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
            .background(
                // Ripple — pill'in arkasında genişleyen halka.
                Capsule()
                    .stroke(state.tint.color, lineWidth: 2)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .help(state.helpText)
        .accessibilityLabel(state.label)
        .onChange(of: pulseTrigger) { _, newValue in
            guard newValue != nil else { return }
            // Reset → animate. SwiftUI animasyonun başlamasını garantilemek
            // için state değişiminin sonrasında withAnimation çağrılır.
            pulseScale = 1.0
            pulseOpacity = 0.85
            withAnimation(.easeOut(duration: 1.6)) {
                pulseScale = 1.7
                pulseOpacity = 0
            }
        }
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

/// **Sprint 4:** Bağlantı state geçişlerinden hangilerinin "kayıp event"
/// olarak işaretleneceğini hesaplayan saf yardımcı. Yalnızca .connected'tan
/// .disconnected'a düşüş "kullanıcı dikkati gerektirir" sayılır; aktif
/// disconnect (kullanıcının "Bağlantıyı kapat" tıklaması) ya da pair
/// reset (notPaired) bunun dışında kalır.
enum ConnectionTransitionDetector {
    static func isLossEvent(
        from oldState: ConnectionPillState,
        to newState: ConnectionPillState
    ) -> Bool {
        oldState == .connected && newState == .disconnected
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
