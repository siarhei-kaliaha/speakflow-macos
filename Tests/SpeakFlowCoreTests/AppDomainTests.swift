import XCTest
@testable import SpeakFlowCore

final class AppDomainTests: XCTestCase {
    func testHotkeyBindingDisplayNamesAreStable() {
        XCTAssertEqual(HotkeyBinding.fn.displayName, "Fn / Globe")
        XCTAssertEqual(HotkeyBinding.ctrlOptionSpace.displayName, "Ctrl+Option+Space")
        XCTAssertEqual(HotkeyBinding.rightCommand.displayName, "Right Command")
        XCTAssertEqual(HotkeyBinding.rightControl.displayName, "Right Control")
    }

    func testSpeakFlowErrorDescriptionsAreReadable() {
        XCTAssertTrue(SpeakFlowError.missingAPIKey.localizedDescription.contains("API key"))
        XCTAssertTrue(SpeakFlowError.invalidBaseURL("bad").localizedDescription.contains("bad"))
        XCTAssertTrue(SpeakFlowError.transcriptionFailed("oops").localizedDescription.contains("oops"))
        XCTAssertTrue(SpeakFlowError.cleanupFailed("oops").localizedDescription.contains("oops"))
        XCTAssertTrue(SpeakFlowError.noRecordedFile.localizedDescription.contains("no audio file"))
    }
}
