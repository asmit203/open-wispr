import Foundation

public enum AssistantInvocationMode: String, Codable, CaseIterable {
    case wakePhrase
    case assistantHotkey
    case intentDetect
}

public enum AssistantOutputMode: String, Codable, CaseIterable {
    case dashboard
    case insert
    case copy
    case none
}

public enum SkillKind: String, Codable, CaseIterable {
    case shell
    case shortcut
    case codex
}

public enum SkillPassTranscriptAs: String, Codable, CaseIterable {
    case env
    case finalArg
}

public enum AssistantInvocationSource: String, Codable {
    case wakePhrase
    case assistantHotkey
    case intentDetect
    case dashboard
}

public struct CodexRunnerConfig: Codable, Equatable {
    public var command: String
    public var args: [String]
    public var model: String?
    public var workingDirectory: String?
    public var includeTranscriptInArgs: Bool?
    public var timeoutSeconds: Int?

    public init(
        command: String = "",
        args: [String] = [],
        model: String? = nil,
        workingDirectory: String? = nil,
        includeTranscriptInArgs: Bool? = nil,
        timeoutSeconds: Int? = nil
    ) {
        self.command = command
        self.args = args
        self.model = model
        self.workingDirectory = workingDirectory
        self.includeTranscriptInArgs = includeTranscriptInArgs
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct AssistantConfig: Codable, Equatable {
    public var enabled: Bool?
    public var invocationModes: [AssistantInvocationMode]?
    public var wakePhrase: String?
    public var hotkey: HotkeyConfig?
    public var defaultOutputMode: AssistantOutputMode?
    public var skillsDirectory: String?
    public var historyFile: String?
    public var codexRunner: CodexRunnerConfig?
    public var intentDetectEnabled: Bool?
    public var autoRunDeterministicSkills: Bool?

    public init(
        enabled: Bool? = nil,
        invocationModes: [AssistantInvocationMode]? = nil,
        wakePhrase: String? = nil,
        hotkey: HotkeyConfig? = nil,
        defaultOutputMode: AssistantOutputMode? = nil,
        skillsDirectory: String? = nil,
        historyFile: String? = nil,
        codexRunner: CodexRunnerConfig? = nil,
        intentDetectEnabled: Bool? = nil,
        autoRunDeterministicSkills: Bool? = nil
    ) {
        self.enabled = enabled
        self.invocationModes = invocationModes
        self.wakePhrase = wakePhrase
        self.hotkey = hotkey
        self.defaultOutputMode = defaultOutputMode
        self.skillsDirectory = skillsDirectory
        self.historyFile = historyFile
        self.codexRunner = codexRunner
        self.intentDetectEnabled = intentDetectEnabled
        self.autoRunDeterministicSkills = autoRunDeterministicSkills
    }

    public var isEnabled: Bool {
        enabled ?? false
    }

    public var resolvedInvocationModes: [AssistantInvocationMode] {
        var modes = invocationModes ?? []
        if (intentDetectEnabled ?? false), !modes.contains(.intentDetect) {
            modes.append(.intentDetect)
        }
        if modes.isEmpty, isEnabled {
            modes = [.wakePhrase]
        }
        return modes
    }

    public var resolvedWakePhrase: String {
        let raw = wakePhrase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "open wispr" : raw
    }

    public var resolvedDefaultOutputMode: AssistantOutputMode {
        defaultOutputMode ?? .dashboard
    }

    public var shouldAutoRunDeterministicSkills: Bool {
        autoRunDeterministicSkills ?? true
    }

    public var resolvedSkillsDirectory: URL {
        if let skillsDirectory, !skillsDirectory.isEmpty {
            return URL(fileURLWithPath: NSString(string: skillsDirectory).expandingTildeInPath)
        }
        return Config.configDir.appendingPathComponent("skills", isDirectory: true)
    }

    public var resolvedHistoryFile: URL {
        if let historyFile, !historyFile.isEmpty {
            return URL(fileURLWithPath: NSString(string: historyFile).expandingTildeInPath)
        }
        return Config.configDir.appendingPathComponent("assistant-history.jsonl")
    }

    public var resolvedCodexTimeout: Int {
        let timeout = codexRunner?.timeoutSeconds ?? 120
        return max(timeout, 1)
    }

    public var codexIncludesTranscriptInArgs: Bool {
        codexRunner?.includeTranscriptInArgs ?? true
    }
}

public struct SkillDefinition: Equatable {
    public var id: String
    public var title: String
    public var description: String
    public var kind: SkillKind
    public var enabled: Bool
    public var triggers: [String]
    public var requiresConfirmation: Bool
    public var outputMode: AssistantOutputMode
    public var timeoutSeconds: Int?
    public var command: String?
    public var args: [String]
    public var shortcutName: String?
    public var workingDirectory: String?
    public var passTranscriptAs: SkillPassTranscriptAs
    public var trusted: Bool
    public var body: String
    public var sourceURL: URL?

    public init(
        id: String,
        title: String,
        description: String = "",
        kind: SkillKind,
        enabled: Bool = true,
        triggers: [String],
        requiresConfirmation: Bool = false,
        outputMode: AssistantOutputMode = .dashboard,
        timeoutSeconds: Int? = nil,
        command: String? = nil,
        args: [String] = [],
        shortcutName: String? = nil,
        workingDirectory: String? = nil,
        passTranscriptAs: SkillPassTranscriptAs = .env,
        trusted: Bool = false,
        body: String = "",
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.kind = kind
        self.enabled = enabled
        self.triggers = triggers
        self.requiresConfirmation = requiresConfirmation
        self.outputMode = outputMode
        self.timeoutSeconds = timeoutSeconds
        self.command = command
        self.args = args
        self.shortcutName = shortcutName
        self.workingDirectory = workingDirectory
        self.passTranscriptAs = passTranscriptAs
        self.trusted = trusted
        self.body = body
        self.sourceURL = sourceURL
    }

    public var normalizedTriggers: [String] {
        triggers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var isDeterministic: Bool {
        kind == .shell || kind == .shortcut
    }

    public var effectiveOutputMode: AssistantOutputMode {
        outputMode
    }
}

public struct SkillExecutionRequest: Equatable {
    public var skill: SkillDefinition
    public var input: String
    public var matchedTrigger: String
    public var source: AssistantInvocationSource

    public init(skill: SkillDefinition, input: String, matchedTrigger: String, source: AssistantInvocationSource) {
        self.skill = skill
        self.input = input
        self.matchedTrigger = matchedTrigger
        self.source = source
    }
}

public struct SkillExecutionResult: Codable, Equatable {
    public var skillID: String
    public var skillTitle: String
    public var kind: SkillKind
    public var source: AssistantInvocationSource
    public var input: String
    public var matchedTrigger: String
    public var outputText: String
    public var standardError: String
    public var exitCode: Int32
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        skillID: String,
        skillTitle: String,
        kind: SkillKind,
        source: AssistantInvocationSource,
        input: String,
        matchedTrigger: String,
        outputText: String,
        standardError: String,
        exitCode: Int32,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.skillID = skillID
        self.skillTitle = skillTitle
        self.kind = kind
        self.source = source
        self.input = input
        self.matchedTrigger = matchedTrigger
        self.outputText = outputText
        self.standardError = standardError
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var succeeded: Bool {
        exitCode == 0
    }
}

public struct SkillExecutionHistoryEntry: Codable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var skillID: String
    public var skillTitle: String
    public var kind: SkillKind
    public var source: AssistantInvocationSource
    public var input: String
    public var outputPreview: String
    public var succeeded: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        skillID: String,
        skillTitle: String,
        kind: SkillKind,
        source: AssistantInvocationSource,
        input: String,
        outputPreview: String,
        succeeded: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.skillID = skillID
        self.skillTitle = skillTitle
        self.kind = kind
        self.source = source
        self.input = input
        self.outputPreview = outputPreview
        self.succeeded = succeeded
    }

    public init(result: SkillExecutionResult) {
        self.init(
            timestamp: result.finishedAt,
            skillID: result.skillID,
            skillTitle: result.skillTitle,
            kind: result.kind,
            source: result.source,
            input: result.input,
            outputPreview: String(result.outputText.prefix(160)),
            succeeded: result.succeeded
        )
    }
}

public enum AssistantResolution: Equatable {
    case none
    case matched(SkillExecutionRequest, ambiguous: Bool)
}

enum AssistantError: LocalizedError {
    case invalidSkill(String)
    case unsupportedSkillKind
    case codexRunnerNotConfigured
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSkill(let message):
            return message
        case .unsupportedSkillKind:
            return "Unsupported skill type"
        case .codexRunnerNotConfigured:
            return "Codex runner is not configured"
        case .executionFailed(let message):
            return message
        }
    }
}

extension AssistantConfig {
    public static let defaultConfig = AssistantConfig(
        enabled: false,
        invocationModes: [.wakePhrase],
        wakePhrase: "open wispr",
        hotkey: nil,
        defaultOutputMode: .dashboard,
        skillsDirectory: nil,
        historyFile: nil,
        codexRunner: nil,
        intentDetectEnabled: false,
        autoRunDeterministicSkills: true
    )
}
