import XCTest
@testable import OpenWisprLib

final class AssistantSkillStoreTests: XCTestCase {
    func testParseMarkdownSkillWithFrontmatter() throws {
        let markdown = """
        ---
        id: summarize
        title: Summarize Notes
        description: Turn rough notes into a summary
        kind: codex
        enabled: true
        triggers: ["summarize notes", "summarize this"]
        requiresConfirmation: true
        outputMode: dashboard
        trusted: false
        ---

        Summarize the user's notes into a concise brief.
        """

        let store = AssistantSkillStore()
        let skill = try store.parseSkill(markdown: markdown)
        XCTAssertEqual(skill.id, "summarize")
        XCTAssertEqual(skill.kind, .codex)
        XCTAssertEqual(skill.triggers, ["summarize notes", "summarize this"])
        XCTAssertTrue(skill.requiresConfirmation)
        XCTAssertEqual(skill.body, "Summarize the user's notes into a concise brief.")
    }

    func testSaveAndLoadSkillRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = AssistantConfig(enabled: true, skillsDirectory: root.path)
        let store = AssistantSkillStore()
        let saved = try store.saveSkill(
            SkillDefinition(
                id: "echo-task",
                title: "Echo Task",
                kind: .shell,
                triggers: ["echo task"],
                command: "/bin/echo",
                args: [],
                passTranscriptAs: .finalArg,
                trusted: true
            ),
            for: config
        )

        let loaded = try store.loadSkills(for: config)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, saved.id)
        XCTAssertEqual(loaded[0].command, "/bin/echo")
    }
}
