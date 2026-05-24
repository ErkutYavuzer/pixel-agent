import Foundation

/// Composer'a sürüklenip bırakılan bir dosya/URL için draft'a eklenecek
/// metni üreten saf yardımcı (Sprint 5 — drag-drop file context).
///
/// LLM CLI'ları (Claude/Codex/Gemini) ek dosya kabul etmiyor — sadece
/// text prompt. Bu yüzden dosya içeriği prompt'a embed edilir. Stratejiler:
///
/// - **Text file (whitelisted ext + < 100KB):** fenced code block içinde
///   `// <filename>` header'ı ile inline.
/// - **Diğer dosyalar:** sadece path referansı (`📎 /path/to/file`).
/// - **Klasör:** ilk satırda klasör yolu + tab'la indented file listesi
///   (max 20 entry).
///
/// Saf — `FileManager` enjekte edilebilir (test'ler için).
enum FileDropFormatter {

    /// Inline embedding limiti. Üzeri text dosyası da olsa path referansına
    /// düşer (composer'ı 1MB JSON ile boğmasın).
    static let maxInlineByteSize = 100_000

    /// Klasör drop'unda gösterilecek max dosya sayısı.
    static let maxFolderEntries = 20

    /// Verilen URL için draft'a eklenecek metni döner. URL geçersizse nil.
    static func snippet(
        forFileURL url: URL,
        fileManager: FileManager = .default
    ) -> String? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return nil
        }
        if isDir.boolValue {
            return folderSnippet(url: url, fileManager: fileManager)
        }
        return fileSnippet(url: url, fileManager: fileManager)
    }

    // MARK: - File

    private static func fileSnippet(url: URL, fileManager: FileManager) -> String {
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent
        let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0

        if isLikelyTextFile(extension: ext), size > 0, size < maxInlineByteSize,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            // Fenced code block — Sprint 1/A1 markdown renderer bunu güzel render eder.
            return "```\(codeFenceLanguage(forExtension: ext))\n// \(fileName)\n\(content)\n```\n"
        }
        return "📎 `\(url.path)`"
    }

    // MARK: - Folder

    private static func folderSnippet(url: URL, fileManager: FileManager) -> String {
        let folderName = url.lastPathComponent
        guard let entries = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return "📁 `\(url.path)` (okunamadı)"
        }
        let sorted = entries.sorted()
        let visible = sorted.prefix(maxFolderEntries)
        var lines = ["📁 `\(folderName)/` —"]
        for entry in visible {
            lines.append("  - \(entry)")
        }
        if sorted.count > maxFolderEntries {
            lines.append("  …ve \(sorted.count - maxFolderEntries) dosya daha")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Text file detection

    /// Bu uzantı text içerik içerir mi? Whitelist — false positives güvenli
    /// (binary dosya inline olur), false negatives sadece path olarak gider.
    static func isLikelyTextFile(extension ext: String) -> Bool {
        textFileExtensions.contains(ext.lowercased())
    }

    static let textFileExtensions: Set<String> = [
        // Programming languages
        "swift", "js", "ts", "py", "go", "rs", "c", "cpp", "h", "hpp",
        "java", "kt", "rb", "sh", "bash", "zsh", "fish",
        "php", "lua", "r", "scala", "clj", "ex", "exs", "elm", "hs", "ml",
        // Markup / config / docs
        "md", "txt", "rst", "tex", "asciidoc",
        "json", "yaml", "yml", "toml", "xml", "ini", "conf", "cfg",
        "html", "htm", "css", "scss", "sass", "less",
        // Data
        "csv", "tsv", "log", "diff", "patch",
        // Build / CI
        "gradle", "podspec", "lock",
        // Misc
        "sql", "graphql", "proto",
    ]

    /// Code block fence için language tag. Bilinmeyen uzantılarda boş
    /// string (fence dilsiz `\`\`\``).
    static func codeFenceLanguage(forExtension ext: String) -> String {
        // Çoğu durumda uzantı doğrudan dil adı. Aliases:
        let aliases: [String: String] = [
            "yml": "yaml",
            "htm": "html",
            "scss": "scss",
            "sass": "sass",
            "js": "javascript",
            "ts": "typescript",
            "py": "python",
            "rb": "ruby",
            "rs": "rust",
            "kt": "kotlin",
            "ex": "elixir",
            "exs": "elixir",
            "hs": "haskell",
            "ml": "ocaml",
            "clj": "clojure",
            "tsv": "tsv",
        ]
        let lower = ext.lowercased()
        return aliases[lower] ?? lower
    }
}
