import XCTest
@testable import OpenWisprLib

final class AssistantExecutorTests: XCTestCase {
    func testShellSkillPassesTranscriptAsFinalArg() throws {
        let skill = SkillDefinition(
            id: "echo-task",
            title: "Echo Task",
            kind: .shell,
            triggers: ["echo task"],
            command: "/bin/echo",
            args: [],
            passTranscriptAs: .finalArg,
            trusted: true
        )
        let request = SkillExecutionRequest(
            skill: skill,
            input: "hello world",
            matchedTrigger: "echo task",
            source: .dashboard
        )
        let executor = AssistantExecutor()
        let result = try executor.execute(
            AssistantExecutionContext(
                assistantConfig: AssistantConfig.defaultConfig,
                request: request
            )
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.outputText, "hello world")
    }

    func testCodexSkillRequiresRunnerConfiguration() {
        let skill = SkillDefinition(
            id: "summarize",
            title: "Summarize",
            kind: .codex,
            triggers: ["summarize"],
            body: "Summarize the input."
        )
        let request = SkillExecutionRequest(
            skill: skill,
            input: "notes",
            matchedTrigger: "summarize",
            source: .dashboard
        )
        let executor = AssistantExecutor()
        XCTAssertThrowsError(
            try executor.execute(
                AssistantExecutionContext(
                    assistantConfig: AssistantConfig.defaultConfig,
                    request: request
                )
            )
        )
    }
}
