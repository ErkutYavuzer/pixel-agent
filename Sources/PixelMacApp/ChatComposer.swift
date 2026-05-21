import SwiftUI

struct ChatComposer: View {
    @Binding var draft: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Mesaj yaz...", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSend { onSend() } }
                .disabled(isStreaming)

            if isStreaming {
                Button("Durdur", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button("Gönder", action: onSend)
                    .keyboardShortcut(.return)
                    .disabled(!canSend)
            }
        }
        .padding()
    }
}
