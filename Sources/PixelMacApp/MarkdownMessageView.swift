import AppKit
import SwiftUI

/// Asistan mesajının markdown-aware render'ı (A1).
///
/// Mesaj `MarkdownSegmenter` ile parça parça bölünür; her `.text` segmenti
/// `AttributedString(markdown:)` üzerinden inline formatlama (bold/italic/
/// inline code/link) ile gösterilir, her `.codeBlock` segmenti monospace blok
/// + "Kopyala" butonuyla.
///
/// Streaming sırasında her chunk geldiğinde view re-render olur — saf
/// segmenter idempotent olduğu için güvenli.
struct MarkdownMessageView: View {
    let text: String

    private var segments: [MessageSegment] {
        MarkdownSegmenter.segments(from: text)
    }

    var body: some View {
        if text.isEmpty {
            // Streaming başladı ama henüz token yok — orijinal "…" placeholder.
            Text("…")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let content):
                        InlineMarkdownText(content: content)
                    case .codeBlock(let content, let language):
                        CodeBlockView(content: content, language: language)
                    }
                }
            }
        }
    }
}

/// Tek bir text segmenti. `AttributedString(markdown:)` ile bold/italic/
/// inline code/link parse eder; whitespace korunur (`inlineOnlyPreservingWhitespace`).
/// Parse hatası olursa düz metne düşer (streaming sırasında yarım `*` olabilir).
private struct InlineMarkdownText: View {
    let content: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(content)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Fenced code block render'ı. Monospace, hafif arka plan, sağ üstte
/// "Kopyala" butonu (1.5s "Kopyalandı ✓" feedback'i). Boş içerikte buton
/// disabled.
struct CodeBlockView: View {
    let content: String
    let language: String?

    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Text(content.isEmpty ? " " : content)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("code")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: copy) {
                Label(copied ? "Kopyalandı" : "Kopyala",
                      systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.caption2)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .tint(copied ? .green : .accentColor)
            .disabled(content.isEmpty)
            .help(content.isEmpty ? "Kopyalanacak içerik yok" : "Code bloğu panoya kopyala")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Aynı blok'a tekrar tıklanırsa flag yenilenir — eski reset'i ezme.
            copied = false
        }
    }
}
