import PixelCore
import PixelRemote
import SwiftUI

/// Mac sidebar (Sprint 3 / B2) iOS karşılığı (Sprint 5).
///
/// iOS yerel JSONL store'a sahip değil — Mac'in arşivleri relay/LAN
/// üzerinden `archiveListRequest`/`Response` envelope'larıyla alınır.
/// User bir entry'ye tıklayınca `archiveLoadRequest` → response ile
/// mesajlar dolar; detail screen NavigationLink push edilir.
struct ConversationHistoryViewIOS: View {
    @EnvironmentObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Geçmiş")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await session.requestArchiveList() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(session.isLoadingArchives)
                    }
                }
                .task {
                    if session.archiveEntries.isEmpty {
                        await session.requestArchiveList()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.isLoadingArchives && session.archiveEntries.isEmpty {
            ProgressView("Arşivler yükleniyor…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.archiveEntries.isEmpty {
            emptyState
        } else {
            List {
                ForEach(groupedByKind, id: \.kind) { group in
                    Section(header: Text(kindDisplayName(group.kind))) {
                        ForEach(group.entries) { entry in
                            NavigationLink {
                                ArchiveDetailView(entry: entry)
                                    .environmentObject(session)
                            } label: {
                                row(for: entry)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("Arşiv yok")
                .font(.headline)
            Text("Mac'te \"Yeni sohbet\" tıklandığında oluşan arşivler burada görünür.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(for entry: ArchiveEntryPayload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.firstUserSnippet ?? "(başlıksız)")
                .font(.subheadline)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(formattedDate(epoch: entry.archivedAt))
                Text("·")
                Text("\(entry.messageCount) mesaj")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private struct KindGroup {
        let kind: String
        let entries: [ArchiveEntryPayload]
    }

    private var groupedByKind: [KindGroup] {
        let byKind = Dictionary(grouping: session.archiveEntries, by: { $0.backendKind })
        let priorityOrder = ["claude", "codex", "gemini"]
        var groups: [KindGroup] = []
        for kind in priorityOrder where byKind[kind] != nil {
            // Her grup içinde tarih descending.
            let sorted = byKind[kind]!.sorted { $0.archivedAt > $1.archivedAt }
            groups.append(KindGroup(kind: kind, entries: sorted))
        }
        for (kind, items) in byKind.sorted(by: { $0.key < $1.key })
        where !priorityOrder.contains(kind) {
            let sorted = items.sorted { $0.archivedAt > $1.archivedAt }
            groups.append(KindGroup(kind: kind, entries: sorted))
        }
        return groups
    }

    private func kindDisplayName(_ raw: String) -> String {
        switch raw {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "gemini": return "Gemini"
        default: return raw.capitalized
        }
    }

    private func formattedDate(epoch: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}

/// Seçilen arşivin mesajlarını gösterir — Mac'ten yükle, read-only render.
/// **Sprint 6:** Üstte "Bu sohbete Mac'te devam et" butonu — Mac'te aktif
/// backend'e arşivi yükler (mevcut sohbet arşivlenir).
private struct ArchiveDetailView: View {
    @EnvironmentObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss
    let entry: ArchiveEntryPayload
    @State private var didRequestLoad: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            loadActionBar
            Divider()
            content
        }
        .navigationTitle("Sohbet")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await session.requestArchive(id: entry.id)
        }
    }

    private var loadActionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.forward.circle")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text("Bu sohbete Mac'te devam et")
                    .font(.callout)
                if didRequestLoad {
                    Text("İstek Mac'e gönderildi ✓")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            Button {
                Task {
                    await session.requestArchiveLoadIntoActive(id: entry.id)
                    didRequestLoad = true
                    // 1s'lik feedback'ten sonra sheet'i kapat — kullanıcı
                    // Mac chat tabına dönsün.
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    dismiss()
                }
            } label: {
                Label("Yükle", systemImage: "arrow.down.doc")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(didRequestLoad || !session.isConnected)
            .help(session.isConnected
                  ? "Mac'te bu konuşma aktif olur"
                  : "Mac bağlı değil")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var content: some View {
        if session.loadedArchiveMessages.isEmpty {
            ProgressView("Yükleniyor…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(session.loadedArchiveMessages) { msg in
                        MessageRow(message: msg)
                    }
                }
                .padding(16)
            }
        }
    }
}
