import PixelMemory
import SwiftUI

/// Sprint 7 (B2): Arşivlenmiş konuşmanın etiketlerini düzenleme sheet'i.
/// Mevcut tag chip'leri (X butonu remove) + yeni tag TextField (Enter add) +
/// Kapat. Bir tag girilince normalize edilir (lowercase/trim/dedup).
struct EditTagsSheet: View {
    let entry: ArchivedConversationEntry
    @Binding var draft: [String]
    let onCommit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newTag: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Etiketleri düzenle")
                .font(.headline)

            if let snippet = entry.firstUserSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if draft.isEmpty {
                Text("Etiket yok. Aşağıdan yeni bir etiket ekle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                tagChipFlow
            }

            HStack(spacing: 8) {
                TextField("yeni etiket", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(addCurrent)
                Button("Ekle", action: addCurrent)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(TagNormalizer.normalize(newTag) == nil)
            }

            HStack {
                Spacer()
                Button("Kapat") {
                    onCommit()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 220)
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private var tagChipFlow: some View {
        // SwiftUI'nın `FlowLayout`'u macOS 14'te yok; kısa liste için HStack
        // wrap'i yok ama Grid + adaptive yeterli. 3 sütun grid yeterli.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(draft, id: \.self) { tag in
                tagChip(tag)
            }
        }
    }

    @ViewBuilder
    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.caption)
                .lineLimit(1)
            Button {
                draft.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Etiketi kaldır")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.purple.opacity(0.18), in: Capsule())
    }

    private func addCurrent() {
        guard let normalized = TagNormalizer.normalize(newTag) else { return }
        if !draft.contains(normalized) {
            draft.append(normalized)
            draft.sort()
        }
        newTag = ""
        fieldFocused = true
    }
}
