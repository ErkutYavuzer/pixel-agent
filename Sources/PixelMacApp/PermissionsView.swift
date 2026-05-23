import AppKit
import PixelComputerUse
import SwiftUI

/// Accessibility + Screen Recording izin durumunu gösterir ve eksiklerse
/// kullanıcıyı System Settings'in ilgili paneline yönlendirir (ADR-0026 Faz 2).
///
/// Pixel kendi adına onay veremez — kullanıcı manuel olarak Privacy & Security
/// listesinde PixelAgent.app'i seçmek zorunda. Bu view:
/// 1. Mevcut durumu gösterir (✓ verilmiş, ✗ eksik).
/// 2. Eksik izin için "Aç" butonu — deep-link ile System Settings sayfasını açar.
/// 3. "Yenile" butonu — kullanıcı onay verdikten sonra durumu güncelle.
struct PermissionsView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var status: ComputerUsePermissions.Status = ComputerUsePermissions.status()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("İzinler")
                        .font(.title2.bold())
                    Text("Computer Use için gereken macOS izinleri")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(spacing: 12) {
                permissionRow(
                    icon: "cursorarrow.click.2",
                    title: "Accessibility",
                    description: "UI element bulma, tıklama, yazma. ui_query / ui_click / ui_type için gerekli.",
                    granted: status.accessibility,
                    openAction: openAccessibilitySettings
                )

                permissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "Ekran görüntüsü alma. ui_screenshot için gerekli.",
                    granted: status.screenRecording,
                    openAction: openScreenRecordingSettings
                )
            }

            Divider()

            HStack(spacing: 12) {
                Text(status.allGranted
                     ? "Tüm izinler hazır."
                     : "İzinleri verdikten sonra `Yenile`'ye bas — pixel'i yeniden başlatmana gerek yok.")
                    .font(.callout)
                    .foregroundStyle(status.allGranted ? .green : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    refresh()
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }

                Spacer()

                Button("Kapat") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { refresh() }
    }

    // MARK: - Row

    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        openAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Image(systemName: granted ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundStyle(granted ? .green : .red)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !granted {
                Button("Aç") {
                    openAction()
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
        )
    }

    // MARK: - Actions

    private func refresh() {
        status = ComputerUsePermissions.status()
    }

    private func openAccessibilitySettings() {
        // İlk seferde sistem prompt'u açar; sonraki kez direkt panel.
        _ = ComputerUsePermissions.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openScreenRecordingSettings() {
        _ = ComputerUsePermissions.requestScreenRecording()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
