import PixelRemote
import SwiftUI

/// iOS dashboard'unda bağlantı koptuğunda görünen banner (Sprint 5 —
/// Mac `ConnectionPillView` pulse paterniyle paralel).
///
/// `pulseTrigger` Date değiştiğinde banner'ın arka planı 1.6s'lik bir
/// ripple yapar (opacity 0.85 → 0, scale 1.0 → 1.06) — kullanıcının
/// dikkati ekranın üstüne çekilir. Banner statik kalsa fark edilmesi
/// daha zordu.
struct ConnectionLostBanner: View {
    let pulseTrigger: Date?
    /// **Sprint 11 (v0.2.36):** Bir sonraki reconnection denemesinin yapılacağı
    /// an. Banner countdown'ı bu Date'ten 0.5s periyodla geriye sayar.
    /// nil → "Yeniden bağlanılıyor…" (sayıcı yok).
    let nextReconnectAt: Date?
    let onRetry: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.orange)
            // Sprint 11 (A): TimelineView ile saniye saniye countdown
            // (0.5s'lik tick — saniye değişimini kaçırmaz, fazla render yok).
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(ReconnectCountdownFormatter.message(
                    nextAt: nextReconnectAt,
                    now: context.date
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            Button(action: onRetry) {
                Text("Tekrar Dene")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        // Ripple overlay — pulse tetiklendiğinde banner çevresinde
        // hafif bir glow + scale efekti.
        .overlay(
            Rectangle()
                .stroke(Color.orange, lineWidth: 2)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .allowsHitTesting(false)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .onChange(of: pulseTrigger) { _, newValue in
            guard newValue != nil else { return }
            pulseScale = 1.0
            pulseOpacity = 0.85
            withAnimation(.easeOut(duration: 1.6)) {
                pulseScale = 1.06
                pulseOpacity = 0
            }
        }
        // Banner ilk görüldüğünde de bir kez pulse'la — kullanıcı tab
        // değiştirip geri geldiğinde bile fark eder.
        .onAppear {
            if pulseTrigger != nil {
                pulseScale = 1.0
                pulseOpacity = 0.85
                withAnimation(.easeOut(duration: 1.6)) {
                    pulseScale = 1.06
                    pulseOpacity = 0
                }
            }
        }
    }
}
