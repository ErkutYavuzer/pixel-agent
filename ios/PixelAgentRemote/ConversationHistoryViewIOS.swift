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

    /// Sprint 12 (v0.2.37): Swipe-to-delete + confirmation dialog state.
    @State private var pendingDeleteEntry: ArchiveEntryPayload?

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
                            // Sprint 12 (v0.2.37): swipe-to-delete + onay alert.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeleteEntry = entry
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .confirmationDialog(
                "Bu arşivi sil?",
                isPresented: Binding(
                    get: { pendingDeleteEntry != nil },
                    set: { if !$0 { pendingDeleteEntry = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeleteEntry
            ) { entry in
                Button("Sil", role: .destructive) {
                    Task {
                        await session.deleteArchive(id: entry.id)
                        pendingDeleteEntry = nil
                    }
                }
                Button("İptal", role: .cancel) {
                    pendingDeleteEntry = nil
                }
            } message: { entry in
                let title = IOSArchiveTitleResolver.displayTitle(for: entry)
                Text("\"\(title)\" geri alınamaz şekilde silinecek.")
            }
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
            HStack(spacing: 4) {
                Text(IOSArchiveTitleResolver.displayTitle(for: entry))
                    .font(.subheadline)
                    .lineLimit(2)
                // Sprint 9 (v0.2.34): rename rozet — Mac'le paralel.
                if entry.customTitle != nil {
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple.opacity(0.7))
                }
            }
            HStack(spacing: 6) {
                Text(formattedDate(epoch: entry.archivedAt))
                Text("·")
                Text("\(entry.messageCount) mesaj")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            // Sprint 9 (v0.2.34): tag inline preview (varsa) — Mac'le paralel.
            let tagSummary = IOSArchiveTitleResolver.tagInlineSummary(entry.tags)
            if !tagSummary.isEmpty {
                Text(tagSummary)
                    .font(.caption2)
                    .foregroundStyle(.purple.opacity(0.85))
                    .lineLimit(1)
            }
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
/// **Sprint 10:** Toolbar'da "Düzenle" — rename + tag düzenleme sheet'i.
private struct ArchiveDetailView: View {
    @EnvironmentObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss
    let entry: ArchiveEntryPayload
    @State private var didRequestLoad: Bool = false
    @State private var showEditSheet: Bool = false

    /// `session.archiveEntries`'in güncel halinden bu entry'nin (id eşleşmesi
    /// üzerinden) son hali — Mac değişikliği sonrası listeyi otomatik
    /// günceller, biz buradan en güncel customTitle/tags'i alırız.
    private var liveEntry: ArchiveEntryPayload {
        session.archiveEntries.first(where: { $0.id == entry.id }) ?? entry
    }

    var body: some View {
        VStack(spacing: 0) {
            loadActionBar
            if let tags = liveEntry.tags, !tags.isEmpty {
                tagChipRow(tags: tags)
            }
            Divider()
            content
        }
        .navigationTitle(IOSArchiveTitleResolver.displayTitle(for: liveEntry))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(!session.isConnected)
                .help(session.isConnected ? "Başlık + etiket düzenle" : "Mac bağlı değil")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditArchiveSheet(entry: liveEntry)
                .environmentObject(session)
        }
        .task {
            await session.requestArchive(id: entry.id)
        }
    }

    /// Sprint 9 (v0.2.34): Detail screen üstünde tag chip listesi — readonly
    /// görselleştirme (iOS'tan rename/tag düzenlemesi v0.2.35+ adayı).
    @ViewBuilder
    private func tagChipRow(tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.18), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemGroupedBackground))
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
