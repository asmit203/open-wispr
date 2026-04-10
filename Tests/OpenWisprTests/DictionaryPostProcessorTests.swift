import XCTest
@testable import OpenWisprLib

final class DictionaryPostProcessorTests: XCTestCase {
    func testBuildPromptEmpty() {
        XCTAssertEqual(DictionaryPostProcessor.buildPrompt(from: []), "")
    }

    func testBuildPromptDeduplicatesValues() {
        let entries = [
            DictionaryEntry(from: "nural", to: "neural"),
            DictionaryEntry(from: "nueral", to: "neural"),
            DictionaryEntry(from: "chat gee pee tee", to: "ChatGPT"),
        ]
        XCTAssertEqual(DictionaryPostProcessor.buildPrompt(from: entries), "Vocabulary: ChatGPT, neural.")
    }

    func testSingleWordReplacement() {
        let entries = [DictionaryEntry(from: "nural", to: "neural")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("the nural network", dictionary: entries),
            "the neural network"
        )
    }

    func testMultiWordReplacement() {
        let entries = [DictionaryEntry(from: "chat gee pee tee", to: "ChatGPT")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("I use chat gee pee tee daily", dictionary: entries),
            "I use ChatGPT daily"
        )
    }

    func testGreedyLongestMatchWins() {
        let entries = [
            DictionaryEntry(from: "open", to: "Open"),
            DictionaryEntry(from: "open whisper", to: "OpenWispr"),
        ]
        XCTAssertEqual(
            DictionaryPostProcessor.process("I use open whisper daily", dictionary: entries),
            "I use OpenWispr daily"
        )
    }

    func testTrailingPunctuationPreserved() {
        let entries = [DictionaryEntry(from: "nural", to: "neural")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("it is nural, right?", dictionary: entries),
            "it is neural, right?"
        )
    }

    func testDuplicateFromKeepsFirstEncounteredEntry() {
        let entries = [
            DictionaryEntry(from: "nural", to: "neural"),
            DictionaryEntry(from: "nural", to: "NEURAL"),
        ]
        XCTAssertEqual(
            DictionaryPostProcessor.process("the nural network", dictionary: entries),
            "the neural network"
        )
    }

    func testEmptyInputsPassThrough() {
        XCTAssertEqual(DictionaryPostProcessor.process("", dictionary: [DictionaryEntry(from: "a", to: "b")]), "")
        XCTAssertEqual(DictionaryPostProcessor.process("hello world", dictionary: []), "hello world")
    }
}
