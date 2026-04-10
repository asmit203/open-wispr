import XCTest
@testable import OpenWisprLib

final class ActivityOverlayControllerTests: XCTestCase {
    func testRecordingStateShowsBottomWave() {
        XCTAssertEqual(ActivityOverlayMode.mode(for: .recording), .recordingWave)
    }

    func testMeetingRecordingShowsSmallBlip() {
        XCTAssertEqual(ActivityOverlayMode.mode(for: .meetingRecording), .meetingBlip)
    }

    func testNonCaptureStatesHideOverlay() {
        XCTAssertEqual(ActivityOverlayMode.mode(for: .idle), .hidden)
        XCTAssertEqual(ActivityOverlayMode.mode(for: .transcribing), .hidden)
        XCTAssertEqual(ActivityOverlayMode.mode(for: .meetingStarting), .hidden)
        XCTAssertEqual(ActivityOverlayMode.mode(for: .meetingStopping), .hidden)
        XCTAssertEqual(ActivityOverlayMode.mode(for: .downloading), .hidden)
        XCTAssertEqual(ActivityOverlayMode.mode(for: .waitingForPermission), .hidden)
        XCTAssertEqual(ActivityOverlayMode.mode(for: .copiedToClipboard), .hidden)
        XCTAssertEqual(ActivityOverlayMode.mode(for: .error("boom")), .hidden)
    }
}
