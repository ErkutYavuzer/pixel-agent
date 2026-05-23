import PixelCore
import PixelMascot
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var session: RemoteSession
    @State private var draft: String = ""
    @State private var showAbout: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if !session.isConnected {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.orange)
                    Text("Bağlantı koptu. Yeniden bağlanılıyor...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: {
                        if let pairing = session.pairing {
                            Task { await session.connect(pairing: pairing) }
                        }
                    }) {
                        Text("Tekrar Dene")
                            .font(.footnote.bold())
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(session.messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .background(
                    Color(.systemGroupedBackground)
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                )
                .onChange(of: session.messages.count) {
                    if let last = session.messages.last {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let error = session.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
            }

            Divider()

            // Input / Composer bar
            HStack(spacing: 12) {
                TextField("Mesaj...", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.purple)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .environmentObject(session)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // MascotView integrated in header with dynamic state!
            MascotView(state: session.mascotState, size: 36)
                .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("pixel-agent")
                    .font(.system(.headline, design: .rounded))
                if let label = session.transportLabel {
                    transportBadge(label)
                }
            }
            
            Spacer()
            
            if let code = session.pairing?.code {
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            
            Button { showAbout = true } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func transportBadge(_ label: String) -> some View {
        let color: Color = label == "LAN" ? .green : (label == "Relay" ? .blue : .gray)
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
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
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer()
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(BubbleShape(isUser: true))
                    .shadow(color: .blue.opacity(0.15), radius: 3, x: 0, y: 1)
                    .textSelection(.enabled)
            } else if message.role == .assistant {
                // Assistant message
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(.primary)
                        .clipShape(BubbleShape(isUser: false))
                        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                        .textSelection(.enabled)
                }
                Spacer()
            } else {
                // System message
                Spacer()
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                Spacer()
            }
        }
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }
}

/// Custom bubble shape for iOS premium bubble design
struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        var path = Path()

        if isUser {
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        } else {
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        }
        return path
    }
}
