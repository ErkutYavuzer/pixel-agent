import SwiftUI

struct ChatComposer: View {
    @Binding var draft: String
    let isStreaming: Bool
    var planMode: Bool = false
    let onSend: () -> Void
    let onCancel: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var placeholder: String {
        planMode ? "Plan modu — sadece okuma/araştırma" : "Mesaj yaz..."
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSend { onSend() } }
                .disabled(isStreaming)
                .overlay {
                    if planMode {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.orange.opacity(0.55), lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }

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
