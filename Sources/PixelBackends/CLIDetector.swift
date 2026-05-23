import Foundation

public enum CLIKind: String, CaseIterable, Codable, Sendable {
    case claude
    case codex
    case gemini

    public var executableName: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        }
    }
}

public struct CLIDetector: Sendable {
    public init() {}

    public func locate(_ kind: CLIKind) -> String? {
        for candidate in Self.candidatePaths(for: kind) {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return Self.whichSearch(kind.executableName)
    }

    public func available() -> [CLIKind: String] {
        var result: [CLIKind: String] = [:]
        for kind in CLIKind.allCases {
            if let path = locate(kind) {
                result[kind] = path
            }
        }
        return result
    }

    private static func candidatePaths(for kind: CLIKind) -> [String] {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let directories = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
        ]
        var paths = directories.map { "\($0)/\(kind.executableName)" }

        // Codex Mac app bundle içinde de gelir (Codex.app/Contents/Resources/codex)
        if kind == .codex {
            paths.append("/Applications/Codex.app/Contents/Resources/codex")
        }

        return paths
    }

    private static func whichSearch(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        // **Faz 4.1 fix:** Launchpad context'inde PATH minimal; augmented env ile
        // which de Gemini/Claude'u bulabilsin.
        process.environment = EnvironmentBuilder.augmentedEnvironment()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.availableData
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
