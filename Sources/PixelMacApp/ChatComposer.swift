import SwiftUI

struct ChatComposer: View {
    @Binding var draft: String
    let isStreaming: Bool
    var planMode: Bool = false
    let onSend: () -> Void
    let onCancel: () -> Void

    /// Opsiyonel: arka plan subagent dispatch'i için callback. `nil` ise buton render
    /// edilmez (geriye uyumluluk).
    var onDispatchSubagent: (() -> Void)? = nil

    /// `true` ise subagent butonu disabled — havuz dolu olduğunda kullanılır.
    var subagentDisabled: Bool = false

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
                if let dispatch = onDispatchSubagent {
                    Button(action: dispatch) {
                        Image(systemName: "person.2.wave.2")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canSend || subagentDisabled)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .help(subagentDisabled
                          ? "Subagent havuzu dolu (3/3 aktif)"
                          : "Arka plan subagent başlat (⌘⇧Return)")
                }
                Button("Gönder", action: onSend)
                    .keyboardShortcut(.return)
                    .disabled(!canSend)
            }
        }
        .padding()
    }
}
