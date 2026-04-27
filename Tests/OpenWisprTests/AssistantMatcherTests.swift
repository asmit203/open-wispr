import XCTest
@testable import OpenWisprLib

final class AssistantMatcherTests: XCTestCase {
    func testStripWakePhraseReturnsRemainingInput() {
        let matcher = AssistantMatcher()
        XCTAssertEqual(
            matcher.stripWakePhrase(from: "Open Wispr summarize meeting", wakePhrase: "open wispr"),
            "summarize meeting"
        )
    }

    func testResolveLongestTriggerWins() {
        let matcher = AssistantMatcher()
        let skills = [
            SkillDefinition(id: "open", title: "Open", kind: .shell, triggers: ["open"], command: "/bin/echo"),
            SkillDefinition(id: "open-doc", title: "Open Doc", kind: .shell, triggers: ["open document"], command: "/bin/echo"),
        ]
        let resolution = matcher.resolve(
            transcript: "open document roadmap",
            skills: skills,
            source: .intentDetect
        )
        guard case .matched(let request, let ambiguous) = resolution else {
            return XCTFail("Expected a matched skill")
        }
        XCTAssertFalse(ambiguous)
        XCTAssertEqual(request.skill.id, "open-doc")
        XCTAssertEqual(request.input, "roadmap")
    }

    func testResolveDetectsAmbiguousSameLengthTrigger() {
        let matcher = AssistantMatcher()
        let skills = [
            SkillDefinition(id: "one", title: "One", kind: .shell, triggers: ["create note"], command: "/bin/echo"),
            SkillDefinition(id: "two", title: "Two", kind: .shell, triggers: ["create note"], command: "/bin/echo"),
        ]
        let resolution = matcher.resolve(
            transcript: "create note about launch",
            skills: skills,
            source: .intentDetect
        )
        guard case .matched(_, let ambiguous) = resolution else {
            return XCTFail("Expected a matched skill")
        }
        XCTAssertTrue(ambiguous)
    }
}
