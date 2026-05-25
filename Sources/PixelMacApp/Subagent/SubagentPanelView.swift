import AppKit
import PixelBackends
import PixelCore
import PixelSubagent
import SwiftUI

// MARK: - Status'a SwiftUI rengi

private extension SubagentStatus {
    var tintColor: Color {
        switch self {
        case .pending: return .gray
        case .running: return .accentColor
        case .completed: return .green
        case .budgetExceeded: return .orange
        case .cancelled: return .gray
        case .failed: return .red
        }
    }
}

// MARK: - Panel

/// Composer'ın hemen üstünde yatay scrollable subagent kart şeridi. Boş listede
/// hiçbir şey render etmez (`EmptyView`); ChatHost-level divider'lar da gizlenir.
struct SubagentPanelView: View {
    @ObservedObject var manager: SubagentManager
    @State private var selectedSession: SubagentSession?

    var body: some View {
        if manager.sessions.isEmpty {
            EmptyView()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        capBadge
                        ForEach(manager.sessions) { session in
                            SubagentCardView(
                                session: session,
                                onCancel: { manager.cancel(session.id) },
                                onDismiss: { manager.dismiss(session.id) },
                                onTap: {
                                    if session.status.isTerminal {
                                        selectedSession = session
                                    }
                                }
                            )
                            .id(session.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: manager.sessions.count) {
                    guard let last = manager.sessions.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .trailing)
                    }
                }
            }
            .frame(height: 72)
            .sheet(item: $selectedSession) { session in
                SubagentDetailSheet(
                    session: session,
                    onRemove: {
                        manager.dismiss(session.id)
                        selectedSession = nil
                    }
                )
            }
        }
    }

    private var capBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.wave.2")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(manager.activeCount)/\(manager.maxConcurrent)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.4), in: Capsule())
    }
}

// MARK: - Kart

struct SubagentCardView: View {
    let session: SubagentSession
    let onCancel: () -> Void
    let onDismiss: () -> Void
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    statusIcon
                        .frame(width: 14, height: 14)
                    Text(session.backendKind.displayName)
                        .font(.caption.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    elapsedView
                    Spacer(minLength: 18)
                }
                Text(session.promptPreview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 220, height: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background.secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(session.status.tintColor.opacity(0.55), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { onTap() }
            .help(detailedTooltip)

            actionButton
                .padding(5)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .pending:
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
        default:
            Image(systemName: session.status.symbolName)
                .foregroundStyle(session.status.tintColor)
                .font(.system(size: 12, weight: .semibold))
        }
    }

    /// Running/pending durumda her saniye günceller; terminal durumda son değeri sabit gösterir.
    @ViewBuilder
    private var elapsedView: some View {
        if session.status.isTerminal {
            Text("\(Int(session.elapsedSeconds()))s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                Text("\(Int(session.elapsedSeconds(now: ctx.date)))s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if session.status.isTerminal {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Kartı kaldır")
        } else {
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("İptal et")
        }
    }

    private var detailedTooltip: String {
        var lines = [
            "\(session.status.displayLabel) · \(session.backendKind.displayName)",
            "Prompt: \(session.promptPreview)",
        ]
        if case .failed(let error) = session.status {
            lines.append("Hata: \(error)")
        }
        if session.status.isTerminal {
            lines.append("Süre: \(String(format: "%.1f", session.elapsedSeconds()))s")
            lines.append("Detay için tıkla")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Detail sheet

struct SubagentDetailSheet: View {
    let session: SubagentSession
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismissEnv

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: session.status.symbolName)
                    .foregroundStyle(session.status.tintColor)
                Text(session.status.displayLabel)
                    .font(.headline)
                Spacer()
                Text("\(session.backendKind.displayName) · \(String(format: "%.1f", session.elapsedSeconds()))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox("Prompt") {
                ScrollView {
                    Text(session.prompt)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 60, maxHeight: 120)
            }

            // Faz 5 (v0.2.41): Multi-turn dispatch ise per-turn expand list,
            // aksi halde tek output bloğu (eski davranış).
            if let turns = session.multiTurnTurns, !turns.isEmpty {
                GroupBox("Turn List (\(turns.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(turns.enumerated()), id: \.offset) { idx, turn in
                                turnRow(index: idx + 1, turn: turn)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 200, maxHeight: 420)
                }
            } else {
                GroupBox("Çıktı") {
                    ScrollView {
                        Text(displayedOutput)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180, maxHeight: 400)
                }
            }

            HStack {
                Button("Çıktıyı kopyala") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayedOutput, forType: .string)
                }
                .disabled(displayedOutput.isEmpty)

                Spacer()

                if session.status.isTerminal {
                    Button("Kartı sil", role: .destructive) {
                        onRemove()
                        dismissEnv()
                    }
                }

                Button("Kapat") { dismissEnv() }
                    .keyboardShortcut(.escape)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 440)
    }

    private var displayedOutput: String {
        session.result?.output ?? ""
    }

    /// Faz 5 (v0.2.41): Single turn row — number + outcome badge + duration +
    /// expandable output.
    @ViewBuilder
    private func turnRow(index: Int, turn: TurnResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Turn \(index)")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.18), in: Capsule())
                Text(outcomeLabel(for: turn.outcome))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(outcomeColor(for: turn.outcome).opacity(0.18), in: Capsule())
                    .foregroundStyle(outcomeColor(for: turn.outcome))
                Spacer()
                Text("\(String(format: "%.1f", turn.durationSeconds))s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(turn.output.isEmpty ? "(boş)" : turn.output)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func outcomeLabel(for outcome: TurnResult.Outcome) -> String {
        switch outcome {
        case .completed: return "OK"
        case .budgetExceeded(let r): return "Bütçe (\(r.rawValue))"
        case .cancelled: return "İptal"
        case .failed: return "Hata"
        }
    }

    private func outcomeColor(for outcome: TurnResult.Outcome) -> Color {
        switch outcome {
        case .completed: return .green
        case .budgetExceeded: return .orange
        case .cancelled: return .gray
        case .failed: return .red
        }
    }
}
