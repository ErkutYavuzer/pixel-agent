import PixelMemory
import SwiftUI

/// Sprint 6 (B2): Arşivlenmiş bir konuşmaya kullanıcı başlığı vermek için
/// modal sheet. Plain Enter Kaydet'i tetikler (composer paterniyle aynı);
/// Escape Cancel.
struct RenameArchiveSheet: View {
    let entry: ArchivedConversationEntry
    @Binding var draft: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Konuşmayı yeniden adlandır")
                .font(.headline)

            if let snippet = entry.firstUserSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            TextField("Başlık (boş bırakırsan sıfırlanır)", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(onSave)

            HStack {
                Spacer()
                Button("İptal", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 420)
        .onAppear { fieldFocused = true }
    }
}
