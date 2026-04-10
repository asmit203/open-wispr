import XCTest
@testable import OpenWisprLib

final class TranscriptOverlapResolverTests: XCTestCase {
    func testNoPreviousTextPassesCurrentTextThrough() {
        XCTAssertEqual(
            TranscriptOverlapResolver.trimCurrentText(previousText: nil, currentText: "hello world"),
            "hello world"
        )
    }

    func testNoOverlapPassesCurrentTextThrough() {
        XCTAssertEqual(
            TranscriptOverlapResolver.trimCurrentText(previousText: "hello world", currentText: "new sentence"),
            "new sentence"
        )
    }

    func testTrimsExactPrefixSuffixOverlap() {
        XCTAssertEqual(
            TranscriptOverlapResolver.trimCurrentText(
                previousText: "we should ship this feature",
                currentText: "ship this feature tomorrow morning"
            ),
            "tomorrow morning"
        )
    }

    func testTrimsCaseAndPunctuationInsensitiveOverlap() {
        XCTAssertEqual(
            TranscriptOverlapResolver.trimCurrentText(
                previousText: "This is the end,",
                currentText: "the END tomorrow"
            ),
            "tomorrow"
        )
    }

    func testFullyDuplicatedChunkBecomesEmpty() {
        XCTAssertEqual(
            TranscriptOverlapResolver.trimCurrentText(
                previousText: "hello there general kenobi",
                currentText: "general kenobi"
            ),
            ""
        )
    }

    func testWindowLargeEnoughTrimsMatchingSuffixPrefix() {
        let previous = "alpha beta gamma 1 2 3"
        XCTAssertEqual(
            TranscriptOverlapResolver.trimCurrentText(
                previousText: previous,
                currentText: "1 2 3 tail",
                maxWindowTokens: 3
            ),
            "tail"
        )
    }

    func testWindowTooSmallDoesNotTrimLongerOverlap() {
        let previous = "alpha beta gamma 1 2 3"
        XCTAssertEqual(
            TranscriptOverlapResolver.trimCurrentText(
                previousText: previous,
                currentText: "1 2 3 tail",
                maxWindowTokens: 2
            ),
            "1 2 3 tail"
        )
    }
}
