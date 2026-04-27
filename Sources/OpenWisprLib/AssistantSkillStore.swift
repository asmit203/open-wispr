import Foundation

final class AssistantSkillStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ensureSkillsDirectory(for config: AssistantConfig) throws -> URL {
        let directory = config.resolvedSkillsDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func loadSkills(for config: AssistantConfig) throws -> [SkillDefinition] {
        let directory = try ensureSkillsDirectory(for: config)
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let markdownFiles = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try markdownFiles.map(parseSkill(at:))
    }

    func parseSkill(at url: URL) throws -> SkillDefinition {
        let text = try String(contentsOf: url, encoding: .utf8)
        var skill = try parseSkill(markdown: text)
        skill.sourceURL = url
        return skill
    }

    func parseSkill(markdown: String) throws -> SkillDefinition {
        let (frontmatter, body) = splitFrontmatter(markdown)
        let values = try parseFrontmatter(frontmatter)

        let id = stringValue("id", from: values) ?? slugify(stringValue("title", from: values) ?? "skill")
        let title = stringValue("title", from: values) ?? id
        let description = stringValue("description", from: values) ?? ""
        let kind = SkillKind(rawValue: stringValue("kind", from: values) ?? "") ?? .shell
        let enabled = boolValue("enabled", from: values) ?? true
        let triggers = stringArrayValue("triggers", from: values)
        let requiresConfirmation = boolValue("requiresConfirmation", from: values) ?? false
        let outputMode = AssistantOutputMode(rawValue: stringValue("outputMode", from: values) ?? "") ?? .dashboard
        let timeoutSeconds = intValue("timeoutSeconds", from: values)
        let command = stringValue("command", from: values)
        let args = stringArrayValue("args", from: values)
        let shortcutName = stringValue("shortcutName", from: values)
        let workingDirectory = stringValue("workingDirectory", from: values)
        let passTranscriptAs = SkillPassTranscriptAs(rawValue: stringValue("passTranscriptAs", from: values) ?? "") ?? .env
        let trusted = boolValue("trusted", from: values) ?? false

        let skill = SkillDefinition(
            id: id,
            title: title,
            description: description,
            kind: kind,
            enabled: enabled,
            triggers: triggers,
            requiresConfirmation: requiresConfirmation,
            outputMode: outputMode,
            timeoutSeconds: timeoutSeconds,
            command: command,
            args: args,
            shortcutName: shortcutName,
            workingDirectory: workingDirectory,
            passTranscriptAs: passTranscriptAs,
            trusted: trusted,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try validate(skill: skill)
        return skill
    }

    func renderMarkdown(for skill: SkillDefinition) -> String {
        let body = skill.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = [
            "---",
            "id: \(skill.id)",
            "title: \(escapeFrontmatter(skill.title))",
            "description: \(escapeFrontmatter(skill.description))",
            "kind: \(skill.kind.rawValue)",
            "enabled: \(skill.enabled ? "true" : "false")",
            "triggers: \(renderArray(skill.triggers))",
            "requiresConfirmation: \(skill.requiresConfirmation ? "true" : "false")",
            "outputMode: \(skill.outputMode.rawValue)",
            skill.timeoutSeconds.map { "timeoutSeconds: \($0)" },
            skill.command.map { "command: \(escapeFrontmatter($0))" },
            skill.args.isEmpty ? nil : "args: \(renderArray(skill.args))",
            skill.shortcutName.map { "shortcutName: \(escapeFrontmatter($0))" },
            skill.workingDirectory.map { "workingDirectory: \(escapeFrontmatter($0))" },
            "passTranscriptAs: \(skill.passTranscriptAs.rawValue)",
            "trusted: \(skill.trusted ? "true" : "false")",
            "---",
            "",
            body,
            ""
        ].compactMap { $0 }
        return lines.joined(separator: "\n")
    }

    func saveSkill(_ skill: SkillDefinition, for config: AssistantConfig) throws -> SkillDefinition {
        try validate(skill: skill)
        let directory = try ensureSkillsDirectory(for: config)
        let filename = "\(slugify(skill.id)).md"
        let url = directory.appendingPathComponent(filename)
        let markdown = renderMarkdown(for: skill)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        var saved = skill
        saved.sourceURL = url
        return saved
    }

    func saveSkill(markdown: String, existingURL: URL?, for config: AssistantConfig) throws -> SkillDefinition {
        var skill = try parseSkill(markdown: markdown)
        if let existingURL, existingURL.lastPathComponent != "\(slugify(skill.id)).md" {
            try? fileManager.removeItem(at: existingURL)
        }
        skill = try saveSkill(skill, for: config)
        return skill
    }

    func deleteSkill(_ skill: SkillDefinition) throws {
        guard let url = skill.sourceURL, fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func validate(skill: SkillDefinition) throws {
        guard !skill.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistantError.invalidSkill("Skill is missing an id")
        }
        guard !skill.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistantError.invalidSkill("Skill is missing a title")
        }
        guard !skill.normalizedTriggers.isEmpty else {
            throw AssistantError.invalidSkill("Skill must define at least one trigger")
        }
        switch skill.kind {
        case .shell:
            guard let command = skill.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
                throw AssistantError.invalidSkill("Shell skill requires a command")
            }
        case .shortcut:
            guard let shortcutName = skill.shortcutName?.trimmingCharacters(in: .whitespacesAndNewlines), !shortcutName.isEmpty else {
                throw AssistantError.invalidSkill("Shortcut skill requires a shortcutName")
            }
        case .codex:
            break
        }
    }

    private func splitFrontmatter(_ markdown: String) -> (String, String) {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first == "---" else {
            return ("", markdown)
        }

        var frontmatterLines: [String] = []
        var index = 1
        while index < lines.count, lines[index] != "---" {
            frontmatterLines.append(lines[index])
            index += 1
        }
        if index >= lines.count {
            return ("", markdown)
        }
        let body = lines.suffix(from: index + 1).joined(separator: "\n")
        return (frontmatterLines.joined(separator: "\n"), body)
    }

    private func parseFrontmatter(_ frontmatter: String) throws -> [String: String] {
        var result: [String: String] = [:]
        for line in frontmatter.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let separator = trimmed.firstIndex(of: ":") else {
                throw AssistantError.invalidSkill("Invalid frontmatter line: \(trimmed)")
            }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = stripQuotes(value)
        }
        return result
    }

    private func stringValue(_ key: String, from values: [String: String]) -> String? {
        guard let value = values[key], !value.isEmpty else { return nil }
        return value
    }

    private func boolValue(_ key: String, from values: [String: String]) -> Bool? {
        guard let value = values[key]?.lowercased() else { return nil }
        switch value {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private func intValue(_ key: String, from values: [String: String]) -> Int? {
        guard let value = values[key] else { return nil }
        return Int(value)
    }

    private func stringArrayValue(_ key: String, from values: [String: String]) -> [String] {
        guard let value = values[key], !value.isEmpty else { return [] }
        if value.first == "[", let data = value.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array
        }
        return value
            .split(separator: ",")
            .map { stripQuotes(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func stripQuotes(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private func renderArray(_ values: [String]) -> String {
        let quoted = values.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        return "[\(quoted.joined(separator: ", "))]"
    }

    private func escapeFrontmatter(_ value: String) -> String {
        if value.contains(":") || value.contains("\"") || value.contains("[") || value.contains("]") || value.contains(",") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func slugify(_ value: String) -> String {
        let lowered = value.lowercased()
        let pieces = lowered.split { !$0.isLetter && !$0.isNumber }
        let slug = pieces.joined(separator: "-")
        return slug.isEmpty ? "skill" : slug
    }
}
