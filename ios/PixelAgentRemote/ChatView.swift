import PixelCore
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var session: RemoteSession
    @State private var draft: String = ""
    @State private var showAbout: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: session.messages.count) {
                    if let last = session.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let error = session.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Mesaj...", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button("Gönder") { sendDraft() }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .environmentObject(session)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("pixel-agent")
                .font(.headline)
            if let label = session.transportLabel {
                transportBadge(label)
            }
            Spacer()
            if let code = session.pairing?.code {
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// "LAN" yeşil (yerel ağ, düşük gecikme); "Relay" mavi (internet üzeri Cloudflare Worker).
    @ViewBuilder
    private func transportBadge(_ label: String) -> some View {
        let color: Color = label == "LAN" ? .green : (label == "Relay" ? .blue : .gray)
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: .capsule)
            .accessibilityLabel("Bağlantı tipi: \(label)")
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await session.send(text: text) }
    }
}

private struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(badgeColor, in: .capsule)

            Text(message.text)
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
