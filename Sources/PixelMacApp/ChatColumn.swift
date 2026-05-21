import PixelCore
import PixelMascot
import SwiftUI

struct ChatColumn: View {
    @ObservedObject var viewModel: ChatViewModel
    var title: String?
    var showNewButton: Bool = true

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
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.last?.text) {
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let streamError = viewModel.streamError {
                Text(streamError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .task { await viewModel.restoreIfNeeded() }
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor, in: .capsule)

            Text(message.text.isEmpty ? "…" : message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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
