import Foundation

/// Bir asistan mesajını render etmek için ayrılan parça türü.
///
/// `text` segmentleri inline markdown ile (AttributedString) gösterilir,
/// `codeBlock` ayrı bir blok view'da (monospace + kopyala butonu).
enum MessageSegment: Equatable, Sendable {
    case text(String)
    case codeBlock(content: String, language: String?)
}

/// Asistan mesajının düz metin gövdesini fenced code block (` ``` `) sınırlarında
/// böler. Saf yardımcı — SwiftUI'a bağımlı değil, hermetik test edilebilir.
///
/// Davranış:
/// - Açma fence'i satır başında en az `\` ```\ ` olmalı (CommonMark uyumlu);
///   opsiyonel dil etiketi (örn. `\` ```swift\ `) language alanına geçer.
/// - Açma fence'i kapatılmadan metin biterse (streaming durumu) → kalan içerik
///   `codeBlock` olarak emit edilir; UI hâlâ tutarlı görünür.
/// - Ardışık fence çiftleri boş bir code block üretir (`content: ""`).
/// - Boş text buffer'ları emit edilmez (segmentler arasında temiz sınır).
enum MarkdownSegmenter {
    static func segments(from text: String) -> [MessageSegment] {
        var result: [MessageSegment] = []
        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String? = nil
        var inCode = false

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            let combined = textBuffer.joined(separator: "\n")
            if !combined.isEmpty {
                result.append(.text(combined))
            }
            textBuffer.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            let combined = codeBuffer.joined(separator: "\n")
            result.append(.codeBlock(content: combined, language: codeLanguage))
            codeBuffer.removeAll(keepingCapacity: true)
            codeLanguage = nil
        }

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushText()
                    let lang = String(trimmed.dropFirst(3))
                        .trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    inCode = true
                }
            } else {
                if inCode {
                    codeBuffer.append(line)
                } else {
                    textBuffer.append(line)
                }
            }
        }

        // Streaming: açık kalan fence içeriğini code block olarak emit et.
        if inCode {
            flushCode()
        } else {
            flushText()
        }

        return result
    }
}
