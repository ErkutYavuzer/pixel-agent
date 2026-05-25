import PixelBackends
import PixelCore
import PixelMemory
import SwiftUI

/// Arşivlenmiş conversation'ların listesi + seçilen birinin read-only
/// görüntüsü (B2 — conversation history sidebar).
///
/// "Sidebar" terimi audit'ten geliyor; bu MVP'de modal sheet içinde
/// `NavigationSplitView` ile sağlanır (compact). İleride NavigationSplitView
/// ana pencereye terfi ettirilebilir.
struct ConversationHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    /// **Sprint 4 (B2 follow-up):** "Bu sohbete devam et" butonu için
    /// callback. nil ise buton gizli (eski davranış — read-only viewer).
    var onLoadArchive: ((ArchivedConversationEntry) -> Void)? = nil

    @State private var entries: [ArchivedConversationEntry] = []
    @State private var selectedID: ArchivedConversationEntry.ID?
    @State private var selectedMessages: [Message] = []
    @State private var loadError: String?
    @State private var isLoading: Bool = false

    /// Sprint 6 (B2): Rename sheet state.
    @State private var renameTarget: ArchivedConversationEntry?
    @State private var renameDraft: String = ""

    /// Sprint 7 (B2): Tag sheet state + sidebar filter state.
    @State private var editTagsTarget: ArchivedConversationEntry?
    @State private var editTagsDraft: [String] = []
    @State private var activeTagFilter: Set<String> = []
    @State private var availableTags: [String] = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kapat") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 480, idealHeight: 560)
        .task { await reload() }
        .sheet(item: $renameTarget) { entry in
            RenameArchiveSheet(
                entry: entry,
                draft: $renameDraft,
                onSave: { applyRename(for: entry, title: renameDraft) },
                onCancel: { renameTarget = nil }
            )
        }
        .sheet(item: $editTagsTarget) { entry in
            EditTagsSheet(
                entry: entry,
                draft: $editTagsDraft,
                onCommit: {
                    applyTags(for: entry, tags: editTagsDraft)
                    editTagsTarget = nil
                }
            )
        }
    }

    private func applyRename(for entry: ArchivedConversationEntry, title: String?) {
        do {
            try ConversationStore.renameArchive(at: entry.id, title: title)
            renameTarget = nil
            Task { await reload() }
        } catch {
            loadError = "Yeniden adlandırma başarısız: \(error.localizedDescription)"
        }
    }

    private func applyTags(for entry: ArchivedConversationEntry, tags: [String]) {
        let normalized = TagNormalizer.normalize(tags)
        do {
            try ConversationStore.setTags(normalized.isEmpty ? nil : normalized, for: entry.id)
            Task { await reload() }
        } catch {
            loadError = "Etiket kaydedilirken hata: \(error.localizedDescription)"
        }
    }

    /// Sidebar filter uygulanmış entry listesi (groupedByKind bunu kullanır).
    private var filteredEntries: [ArchivedConversationEntry] {
        TagFilter.apply(entries: entries, activeTags: activeTagFilter)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            if !availableTags.isEmpty {
                tagFilterBar
                Divider()
            }
            Group {
                if entries.isEmpty && !isLoading {
                    emptyState
                } else if filteredEntries.isEmpty {
                    filteredEmptyState
                } else {
                    List(selection: $selectedID) {
                        ForEach(groupedByKind, id: \.kind) { group in
                            Section(header: Text(kindDisplayName(group.kind))) {
                                ForEach(group.entries) { entry in
                                    row(for: entry)
                                        .tag(entry.id)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        }
        .frame(minWidth: 260, idealWidth: 300)
        .navigationTitle("Geçmiş")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Listeyi yenile")
                .disabled(isLoading)
            }
        }
        .onChange(of: selectedID) { _, newID in
            guard let id = newID,
                  let entry = entries.first(where: { $0.id == id }) else {
                selectedMessages = []
                return
            }
            loadSelected(entry: entry)
        }
    }

    /// Sprint 7: Etiket filter chip bar (sidebar üstü). availableTags varsa görünür.
    @ViewBuilder
    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(availableTags, id: \.self) { tag in
                    let selected = activeTagFilter.contains(tag)
                    Button {
                        if selected { activeTagFilter.remove(tag) }
                        else { activeTagFilter.insert(tag) }
                    } label: {
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundStyle(selected ? Color.white : .primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        selected ? Color.purple : Color.purple.opacity(0.15),
                        in: Capsule()
                    )
                }
                if !activeTagFilter.isEmpty {
                    Button {
                        activeTagFilter = []
                    } label: {
                        Label("Temizle", systemImage: "xmark.circle")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tag.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Filtreyle eşleşen konuşma yok")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Filtreyi temizle") { activeTagFilter = [] }
                .controlSize(.small)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("Arşiv boş")
                .font(.headline)
            Text("Mevcut sohbeti arşivlemek için ana pencerede \"Yeni sohbet\" butonunu kullan.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(for entry: ArchivedConversationEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(ArchiveTitleResolver.displayTitle(for: entry))
                    .font(.subheadline)
                    .lineLimit(2)
                if entry.customTitle != nil {
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple.opacity(0.7))
                        .help("Yeniden adlandırılmış")
                }
            }
            HStack(spacing: 6) {
                Text(Self.dateFormatter.string(from: entry.archivedAt))
                Text("·")
                Text("\(entry.messageCount) mesaj")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // Sprint 7: Tag inline line — kısa & truncated.
            if !entry.tags.isEmpty {
                Text(tagInlineSummary(entry.tags))
                    .font(.caption2)
                    .foregroundStyle(.purple.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                renameDraft = entry.customTitle ?? ""
                renameTarget = entry
            } label: {
                Label("Yeniden adlandır…", systemImage: "pencil")
            }
            if entry.customTitle != nil {
                Button(role: .destructive) {
                    applyRename(for: entry, title: nil)
                } label: {
                    Label("Başlığı sıfırla", systemImage: "arrow.uturn.backward")
                }
            }
            Divider()
            Button {
                editTagsDraft = entry.tags
                editTagsTarget = entry
            } label: {
                Label("Etiketleri düzenle…", systemImage: "tag")
            }
            if !entry.tags.isEmpty {
                Button(role: .destructive) {
                    applyTags(for: entry, tags: [])
                } label: {
                    Label("Tüm etiketleri sıfırla", systemImage: "tag.slash")
                }
            }
        }
    }

    /// Sprint 7: Row'da gösterilen kısa tag özeti. İlk 3 tag + fazlası "+N" suffix.
    nonisolated private func tagInlineSummary(_ tags: [String]) -> String {
        let visible = tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
        if tags.count > 3 {
            return "\(visible) +\(tags.count - 3)"
        }
        return visible
    }

    // MARK: - Detail (read-only message viewer)

    private var detail: some View {
        Group {
            if let id = selectedID,
               let entry = entries.first(where: { $0.id == id }) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedMessages.isEmpty {
                    Text("Bu arşivde mesaj yok.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Sprint 4 (B2 follow-up): yükle butonu — onLoadArchive
                        // bağlıysa görünür. Mevcut sohbet arşivlenir, archive
                        // mesajlar aktif backend'e taşınır.
                        if let onLoadArchive {
                            loadActionBar(for: entry, onLoad: onLoadArchive)
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(selectedMessages) { msg in
                                    MessageRow(message: msg)
                                }
                            }
                            .padding()
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("Bir konuşma seç")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 400)
    }

    @ViewBuilder
    private func loadActionBar(
        for entry: ArchivedConversationEntry,
        onLoad: @escaping (ArchivedConversationEntry) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.forward.circle")
                .foregroundStyle(.purple)
            Text("Bu sohbete devam et")
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                onLoad(entry)
                dismiss()
            } label: {
                Label("Yükle", systemImage: "arrow.down.doc")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Mevcut sohbet arşivlenir, bu konuşma \(kindDisplayName(entry.backendKind)) için aktif olur")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(
            Rectangle()
                .fill(.secondary.opacity(0.12))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try ConversationStore.listAllArchives()
            // Sprint 7: filter chip bar listesini güncelle.
            availableTags = ConversationStore.listAllTags()
            // Aktif filter'da artık var olmayan tag'leri at (silinmiş arşiv vb.).
            activeTagFilter = activeTagFilter.intersection(Set(availableTags))
            // Auto-select first
            if selectedID == nil, let first = entries.first {
                selectedID = first.id
            }
        } catch {
            loadError = "Arşiv listelenirken hata: \(error.localizedDescription)"
            entries = []
            availableTags = []
            activeTagFilter = []
        }
    }

    private func loadSelected(entry: ArchivedConversationEntry) {
        isLoading = true
        loadError = nil
        let url = entry.id
        Task.detached {
            let decoder = JSONDecoder()
            let data = (try? Data(contentsOf: url)) ?? Data()
            let lines = data.split(separator: 0x0A).filter { !$0.isEmpty }
            var messages: [Message] = []
            for line in lines {
                if let m = try? decoder.decode(Message.self, from: Data(line)) {
                    messages.append(m)
                }
            }
            await MainActor.run {
                selectedMessages = messages
                isLoading = false
            }
        }
    }

    // MARK: - Helpers

    private struct KindGroup {
        let kind: String
        let entries: [ArchivedConversationEntry]
    }

    private var groupedByKind: [KindGroup] {
        let byKind = Dictionary(grouping: filteredEntries, by: { $0.backendKind })
        // Sıra: Claude → Codex → Gemini → diğerleri alfabetik.
        let priorityOrder = ["claude", "codex", "gemini"]
        var groups: [KindGroup] = []
        for kind in priorityOrder where byKind[kind] != nil {
            groups.append(KindGroup(kind: kind, entries: byKind[kind]!))
        }
        for (kind, items) in byKind.sorted(by: { $0.key < $1.key })
        where !priorityOrder.contains(kind) {
            groups.append(KindGroup(kind: kind, entries: items))
        }
        return groups
    }

    private func kindDisplayName(_ raw: String) -> String {
        CLIKind(rawValue: raw)?.displayName ?? raw.capitalized
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "tr_TR")
        return f
    }()
}
