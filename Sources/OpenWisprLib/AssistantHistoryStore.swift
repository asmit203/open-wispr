import Foundation

final class AssistantHistoryStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadEntries(for config: AssistantConfig) -> [SkillExecutionHistoryEntry] {
        let url = config.resolvedHistoryFile
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(SkillExecutionHistoryEntry.self, from: Data(line.utf8))
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func append(result: SkillExecutionResult, for config: AssistantConfig) throws {
        let url = config.resolvedHistoryFile
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        let entry = SkillExecutionHistoryEntry(result: result)
        let data = try encoder.encode(entry)
        guard let line = String(data: data, encoding: .utf8) else {
            throw AssistantError.executionFailed("Could not encode assistant history")
        }
        let payload = line + "\n"
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(Data(payload.utf8))
        } else {
            try payload.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
