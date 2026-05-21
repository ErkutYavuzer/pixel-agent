import Foundation
import PixelCore

public actor ConversationStore {
    public let directory: URL
    public let fileURL: URL
    public let archiveDirectory: URL

    public init(directory: URL? = nil, fileName: String = "conversation.jsonl") throws {
        let baseDir = directory ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let archive = baseDir.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        self.directory = baseDir
        self.fileURL = baseDir.appendingPathComponent(fileName)
        self.archiveDirectory = archive

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    public func append(_ message: Message) throws {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)  // newline
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public func loadAll(limit: Int? = nil) throws -> [Message] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }

        let decoder = JSONDecoder()
        let lines = data.split(separator: 0x0A)
        var messages: [Message] = []
        for line in lines {
            guard !line.isEmpty else { continue }
            if let message = try? decoder.decode(Message.self, from: Data(line)) {
                messages.append(message)
            }
        }
        if let limit, messages.count > limit {
            return Array(messages.suffix(limit))
        }
        return messages
    }

    public func newConversation() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            return
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? Int) ?? 0
        if size > 0 {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
            let stamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension
            let archiveURL = archiveDirectory.appendingPathComponent("\(baseName)-\(stamp).\(ext)")
            try FileManager.default.moveItem(at: fileURL, to: archiveURL)
        } else {
            try FileManager.default.removeItem(at: fileURL)
        }
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    public func messageCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
        let data = try Data(contentsOf: fileURL)
        return data.split(separator: 0x0A).filter { !$0.isEmpty }.count
    }

    public nonisolated static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("pixel-agent", isDirectory: true)
    }
}
