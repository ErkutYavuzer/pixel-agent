import AppKit
import PixelBackends
import PixelCore
import PixelMascot
import SwiftUI

struct ChatColumn: View {
    @ObservedObject var viewModel: ChatViewModel
    var title: String?
    var showNewButton: Bool = true
    /// C9: bilinirse auth hatası tespitinde "<Backend>'a Giriş Yap" butonu
    /// için kullanılır. nil → buton gizli (eski davranış).
    var backendKind: CLIKind? = nil

    /// B6: "Son yanıtı kopyala" butonunda 1.5s feedback state'i tutar.
    /// IntegrationView / CodeBlockView ile aynı pattern.
    @State private var didCopyLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let title {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                }
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                copyLastButton
                if showNewButton {
                    Button(action: viewModel.newConversation) {
                        Image(systemName: "plus.bubble")
                    }
                    .buttonStyle(.borderless)
                    .help("Yeni sohbet (mevcut arşivlenir)")
                    .disabled(viewModel.isStreaming)
                }
                MascotView(state: viewModel.mascotState, size: 32)
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        EmptyChatView { prompt in
                            viewModel.draft = prompt
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { msg in
                                MessageRow(
                                    message: msg,
                                    isStreaming: StreamingMessageHelper.isStreamingTail(
                                        message: msg,
                                        in: viewModel.messages,
                                        isStreaming: viewModel.isStreaming
                                    )
                                )
                                .id(msg.id)
                            }
                        }
                        .padding()
                    }
                }
                .onChange(of: viewModel.messages.last?.text) {
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let streamError = viewModel.streamError {
                let authBackend: CLIKind? = (backendKind != nil
                    && AuthErrorDetector.isAuthError(streamError)) ? backendKind : nil
                ErrorRetryBanner(
                    message: streamError,
                    canRetry: !viewModel.isStreaming
                        && RetryHelper.candidateRetryText(messages: viewModel.messages) != nil,
                    onRetry: viewModel.retryLastSend,
                    onDismiss: viewModel.clearError,
                    authenticateLabel: authBackend.map(LoginLauncher.buttonLabel(for:)),
                    onAuthenticate: authBackend.map { kind in { LoginLauncher.launch(for: kind) } }
                )
            }
        }
        .task { await viewModel.restoreIfNeeded() }
        // B5: menü çubuğundan ⌘N geldiğinde — single mode'da tek sütun, dual
        // mode'da her iki sütun da dinler ve kendi store'unu sıfırlar.
        // Streaming aktifken sessiz yutulur ("Yeni sohbet" butonu da disabled).
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newConversation.notificationName)) { _ in
            guard !viewModel.isStreaming else { return }
            viewModel.newConversation()
        }
    }

    // MARK: - Quick actions (B6)

    /// Header'daki "Son yanıtı kopyala" buton — sadece kopyalanabilir bir
    /// asistan mesajı varsa enabled. Tıklayınca panoya yazar ve 1.5s
    /// "Kopyalandı ✓" feedback'i verir.
    @ViewBuilder
    private var copyLastButton: some View {
        let target = MessageActionsHelper.lastCopyableAssistantText(in: viewModel.messages)
        Button(action: copyLastResponse) {
            Image(systemName: didCopyLast ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundStyle(didCopyLast ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        .disabled(target == nil)
        .help(target != nil
              ? "Son yanıtı panoya kopyala"
              : "Kopyalanacak yanıt yok")
    }

    private func copyLastResponse() {
        guard let text = MessageActionsHelper.lastCopyableAssistantText(in: viewModel.messages) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopyLast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if didCopyLast { didCopyLast = false }
        }
    }
}

struct MessageRow: View {
    let message: Message
    /// `true` ise bu mesaj şu an streaming edilen mesaj. Empty + streaming
    /// durumunda assistant body'sinde 3-dot typing indicator render edilir.
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor, in: .capsule)

            messageBody
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // B6: sağ-tık menüsü — her mesaj kopyalanabilir; assistant rolünde
        // ek "ID'yi Kopyala" debugging affordance'ı yok (over-engineering),
        // sadece basit metin kopyası.
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
            } label: {
                Label("Mesajı Kopyala", systemImage: "doc.on.doc")
            }
            .disabled(message.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        switch message.role {
        case .assistant:
            // Markdown render — fenced code block'ları kopya butonlu blok'a,
            // inline formatlamayı (bold/italic/inline code/link) AttributedString'e
            // çevirir. Streaming sırasında her chunk'ta re-segment yapılır.
            MarkdownMessageView(text: message.text, isStreaming: isStreaming)
        case .user, .system:
            Text(message.text.isEmpty ? "…" : message.text)
                .textSelection(.enabled)
        }
    }

    private var badge: String {
        switch message.role {
        case .user: return "SİZ"
        case .assistant: return "PIXEL"
        case .system: return "SYS"
        }
    }

    private var badgeColor: Color {
        switch message.role {
        case .user: return .blue
        case .assistant: return .purple
        case .system: return .gray
        }
    }
}

// MARK: - Empty state (A3)

/// Yeni / temizlenmiş bir sohbette `ChatColumn` boş ekran yerine bunu gösterir.
/// Kullanıcı "ne yapayım şimdi?" sorusunu sormak yerine örnek prompt chip'ine
/// tıklayıp `ChatViewModel.draft`'a doldurabilir.
struct EmptyChatView: View {
    let onPromptSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 16)

            Image(systemName: "sparkles")
                .font(.system(size: 38))
                .foregroundStyle(.purple.opacity(0.75))

            VStack(spacing: 6) {
                Text("Pixel'le sohbete başla")
                    .font(.title3.bold())
                Text("Yazmaya başla — veya örnek bir promptla dene:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(EmptyChatView.suggestedPrompts) { chip in
                    Button(action: { onPromptSelected(chip.prompt) }) {
                        HStack(spacing: 10) {
                            Image(systemName: chip.icon)
                                .frame(width: 22)
                                .foregroundStyle(.purple)
                            Text(chip.label)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 420)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.purple.opacity(0.18), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(chip.prompt)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    /// Catalog — testlerden de erişilebilir, statik.
    static let suggestedPrompts: [PromptChip] = [
        PromptChip(
            id: "summarize-folder",
            label: "Bu klasörü özetle",
            icon: "folder",
            prompt: "Bu klasörü kısa özetle: ana dosyalar, mimari, dikkat çekici noktalar."
        ),
        PromptChip(
            id: "code-review",
            label: "Code review yap",
            icon: "checklist",
            prompt: "Son git diff'imi gözden geçir; bug, güvenlik, performans, kod kokusu açısından."
        ),
        PromptChip(
            id: "plan-research",
            label: "Plan modunda araştırma",
            icon: "list.bullet.clipboard",
            prompt: "Şu konuyu sadece okuma erişimiyle araştır ve bir plan çıkar: <konu>"
        ),
        PromptChip(
            id: "subagent-compare",
            label: "Subagent ile karşılaştır",
            icon: "person.2.wave.2",
            prompt: "İki yaklaşım için arka plana subagent dispatch et ve sonuçları karşılaştır: <yaklaşım A> vs <yaklaşım B>."
        ),
    ]
}

struct PromptChip: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
    let prompt: String
}
