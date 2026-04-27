import Foundation

struct AssistantExecutionContext {
    var assistantConfig: AssistantConfig
    var request: SkillExecutionRequest
}

final class AssistantExecutor {
    func execute(_ context: AssistantExecutionContext) throws -> SkillExecutionResult {
        let request = context.request
        let startedAt = Date()
        let (output, error, status) = try run(context)
        let finishedAt = Date()

        return SkillExecutionResult(
            skillID: request.skill.id,
            skillTitle: request.skill.title,
            kind: request.skill.kind,
            source: request.source,
            input: request.input,
            matchedTrigger: request.matchedTrigger,
            outputText: output.trimmingCharacters(in: .whitespacesAndNewlines),
            standardError: error.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: status,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private func run(_ context: AssistantExecutionContext) throws -> (String, String, Int32) {
        switch context.request.skill.kind {
        case .shell:
            return try runShellSkill(context)
        case .shortcut:
            return try runShortcutSkill(context)
        case .codex:
            return try runCodexSkill(context)
        }
    }

    private func runShellSkill(_ context: AssistantExecutionContext) throws -> (String, String, Int32) {
        let skill = context.request.skill
        guard let command = skill.command, !command.isEmpty else {
            throw AssistantError.invalidSkill("Shell skill requires a command")
        }
        var args = skill.args
        if skill.passTranscriptAs == .finalArg, !context.request.input.isEmpty {
            args.append(context.request.input)
        }
        return try runProcess(
            executable: command,
            args: args,
            workingDirectory: skill.workingDirectory,
            timeoutSeconds: skill.timeoutSeconds ?? 30,
            environment: environment(for: context, promptPayload: nil)
        )
    }

    private func runShortcutSkill(_ context: AssistantExecutionContext) throws -> (String, String, Int32) {
        let skill = context.request.skill
        guard let shortcutName = skill.shortcutName, !shortcutName.isEmpty else {
            throw AssistantError.invalidSkill("Shortcut skill requires a shortcutName")
        }
        let inputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-wispr-shortcut-\(UUID().uuidString).txt")
        try context.request.input.write(to: inputFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: inputFile) }

        return try runProcess(
            executable: "/usr/bin/shortcuts",
            args: ["run", shortcutName, "--input-path", inputFile.path],
            workingDirectory: skill.workingDirectory,
            timeoutSeconds: skill.timeoutSeconds ?? 30,
            environment: environment(for: context, promptPayload: nil)
        )
    }

    private func runCodexSkill(_ context: AssistantExecutionContext) throws -> (String, String, Int32) {
        let config = context.assistantConfig
        guard let runner = config.codexRunner,
              !runner.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistantError.codexRunnerNotConfigured
        }

        var args = runner.args
        if let model = runner.model, !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }

        let payload = codexPromptPayload(for: context.request)
        if config.codexIncludesTranscriptInArgs {
            args.append(payload)
        }

        return try runProcess(
            executable: runner.command,
            args: args,
            workingDirectory: runner.workingDirectory ?? context.request.skill.workingDirectory,
            timeoutSeconds: runner.timeoutSeconds ?? config.resolvedCodexTimeout,
            environment: environment(for: context, promptPayload: payload)
        )
    }

    private func codexPromptPayload(for request: SkillExecutionRequest) -> String {
        let body = request.skill.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = request.input.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return input
        }
        if input.isEmpty {
            return body
        }
        return "\(body)\n\nUser input:\n\(input)"
    }

    private func environment(for context: AssistantExecutionContext, promptPayload: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let request = context.request
        env["OPENWISPR_SKILL_ID"] = request.skill.id
        env["OPENWISPR_SKILL_TITLE"] = request.skill.title
        env["OPENWISPR_INPUT"] = request.input
        env["OPENWISPR_FULL_TRANSCRIPT"] = request.input
        env["OPENWISPR_TRIGGER"] = request.matchedTrigger
        env["OPENWISPR_INVOCATION_SOURCE"] = request.source.rawValue
        if let promptPayload, !promptPayload.isEmpty {
            env["OPENWISPR_CODEX_PROMPT"] = promptPayload
        }
        return env
    }

    private func runProcess(
        executable: String,
        args: [String],
        workingDirectory: String?,
        timeoutSeconds: Int,
        environment: [String: String]
    ) throws -> (String, String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = environment
        if let workingDirectory, !workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: workingDirectory).expandingTildeInPath)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let deadline = DispatchTime.now() + .seconds(max(timeoutSeconds, 1))
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            throw AssistantError.executionFailed("Assistant command timed out")
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (output, error, process.terminationStatus)
    }
}
