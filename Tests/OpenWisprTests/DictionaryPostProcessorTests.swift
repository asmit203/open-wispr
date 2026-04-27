import XCTest
@testable import OpenWisprLib

final class DictionaryPostProcessorTests: XCTestCase {
    func testBuildPromptEmpty() {
        XCTAssertEqual(DictionaryPostProcessor.buildPrompt(from: []), "")
    }

    func testBuildPromptSingleEntry() {
        let entries = [DictionaryEntry(from: "nural", to: "neural")]
        XCTAssertEqual(DictionaryPostProcessor.buildPrompt(from: entries), "Vocabulary: neural.")
    }

    func testBuildPromptMultipleEntries() {
        let entries = [
            DictionaryEntry(from: "nural", to: "neural"),
            DictionaryEntry(from: "kubernetees", to: "Kubernetes"),
        ]
        XCTAssertEqual(DictionaryPostProcessor.buildPrompt(from: entries), "Vocabulary: Kubernetes, neural.")
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

    func testSingleWordReplacementIsCaseInsensitive() {
        let entries = [DictionaryEntry(from: "nural", to: "neural")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("the Nural network", dictionary: entries),
            "the neural network"
        )
    }

    func testSingleWordWithPeriodPreserved() {
        let entries = [DictionaryEntry(from: "nural", to: "neural")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("it is nural.", dictionary: entries),
            "it is neural."
        )
    }

    func testMultiWordReplacement() {
        let entries = [DictionaryEntry(from: "chat gee pee tee", to: "ChatGPT")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("I use chat gee pee tee daily", dictionary: entries),
            "I use ChatGPT daily"
        )
    }

    func testMultiWordReplacementIsCaseInsensitive() {
        let entries = [DictionaryEntry(from: "chat gee pee tee", to: "ChatGPT")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("I use Chat Gee Pee Tee daily", dictionary: entries),
            "I use ChatGPT daily"
        )
    }

    func testMultiWordReplacementWithTrailingPunctuation() {
        let entries = [DictionaryEntry(from: "chat gee pee tee", to: "ChatGPT")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("I use chat gee pee tee.", dictionary: entries),
            "I use ChatGPT."
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

    func testNoMatchPassesThrough() {
        let entries = [DictionaryEntry(from: "nural", to: "neural")]
        XCTAssertEqual(
            DictionaryPostProcessor.process("hello world", dictionary: entries),
            "hello world"
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

    func testMultipleReplacementsInOneSentence() {
        let entries = [
            DictionaryEntry(from: "nural", to: "neural"),
            DictionaryEntry(from: "kubernetees", to: "Kubernetes"),
        ]
        XCTAssertEqual(
            DictionaryPostProcessor.process("nural nets on kubernetees", dictionary: entries),
            "neural nets on Kubernetes"
        )
    }

    func testEmptyInputsPassThrough() {
        XCTAssertEqual(DictionaryPostProcessor.process("", dictionary: [DictionaryEntry(from: "a", to: "b")]), "")
        XCTAssertEqual(DictionaryPostProcessor.process("hello world", dictionary: []), "hello world")
    }
}
