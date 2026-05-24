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

    @State private var entries: [ArchivedConversationEntry] = []
    @State private var selectedID: ArchivedConversationEntry.ID?
    @State private var selectedMessages: [Message] = []
    @State private var loadError: String?
    @State private var isLoading: Bool = false

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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            if entries.isEmpty && !isLoading {
                emptyState
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
            Text(entry.firstUserSnippet ?? "(başlıksız)")
                .font(.subheadline)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(Self.dateFormatter.string(from: entry.archivedAt))
                Text("·")
                Text("\(entry.messageCount) mesaj")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail (read-only message viewer)

    private var detail: some View {
        Group {
            if let id = selectedID, entries.contains(where: { $0.id == id }) {
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
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(selectedMessages) { msg in
                                MessageRow(message: msg)
                            }
                        }
                        .padding()
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

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try ConversationStore.listAllArchives()
            // Auto-select first
            if selectedID == nil, let first = entries.first {
                selectedID = first.id
            }
        } catch {
            loadError = "Arşiv listelenirken hata: \(error.localizedDescription)"
            entries = []
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
        let byKind = Dictionary(grouping: entries, by: { $0.backendKind })
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
