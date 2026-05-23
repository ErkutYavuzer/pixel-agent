import SwiftUI

/// Stream hatası olduğunda ChatColumn'un altında beliren inline banner (A7).
///
/// "Sessiz fail" davranışını kaldırır — kullanıcıya hem hata mesajını
/// gösterir hem de tek tıkla retry imkanı verir. Kapat butonu yalnızca
/// görseli gizler, mesaj listesini olduğu gibi bırakır.
///
/// Demo-readiness kriteri: "Hata durumlarında 'Tekrar dene' butonu (sessiz
/// fail yok)."
struct ErrorRetryBanner: View {
    let message: String
    /// `false` ise "Tekrar dene" butonu disabled — retry adayı yoksa
    /// (örn. tutarsız state, ya da streaming devam ediyorsa) ChatViewModel
    /// no-op davranır; kullanıcıya yine de gösterimde tutmak yerine disabled
    /// veriyoruz.
    var canRetry: Bool = true
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 2)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 4) {
                Button(action: onRetry) {
                    Label("Tekrar dene", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canRetry)
                .help(canRetry
                      ? "Son mesajı yeniden gönder"
                      : "Şu an yeniden gönderilemez")

                Button(action: onDismiss) {
                    Label("Kapat", systemImage: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
