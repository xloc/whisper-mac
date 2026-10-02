import AppKit
import XCTest
@testable import WhisperPTTCore

final class CoreTests: XCTestCase {
    func testPermissionChangesUpdateIdleStatusWithoutMaskingWorkOrErrors() {
        for idle in [PTTStatus.ready, .permissionRequired] {
            XCTAssertEqual(idle.displayed(microphoneAllowed: true, accessibilityAllowed: true), .ready)
            XCTAssertEqual(idle.displayed(microphoneAllowed: false, accessibilityAllowed: true), .permissionRequired)
            XCTAssertEqual(idle.displayed(microphoneAllowed: true, accessibilityAllowed: false), .permissionRequired)
        }
        for active in [PTTStatus.loading, .recording, .transcribing, .sent, .noSpeech, .error] {
            XCTAssertEqual(active.displayed(microphoneAllowed: false, accessibilityAllowed: false), active)
        }
    }

    func testModifierHotkeysFollowModifierState() {
        XCTAssertTrue(Hotkey.rightOption.state(event: .flagsChanged, flags: .option) == true)
        XCTAssertFalse(Hotkey.rightOption.state(event: .flagsChanged, flags: []) == true)
        XCTAssertTrue(Hotkey.rightCommand.state(event: .flagsChanged, flags: .command) == true)
        XCTAssertNil(Hotkey.rightOption.state(event: .keyDown))
    }

    func testFunctionKeyUsesKeyDownAndKeyUp() {
        XCTAssertTrue(Hotkey.f13.state(event: .keyDown) == true)
        XCTAssertTrue(Hotkey.f13.state(event: .keyUp) == false)
        XCTAssertNil(Hotkey.f13.state(event: .flagsChanged))
    }

    func testResampleProducesSixteenKilohertzSamples() {
        let input = (0..<48_000).map(Float.init)
        let output = AudioSamples.resample(input, from: 48_000)
        XCTAssertEqual(output.count, 16_000)
        XCTAssertEqual(output[1], 3, accuracy: 0.001)
    }

    func testTranscriptJoinRemovesSegmentWhitespace() {
        XCTAssertEqual(Transcript.join([" hello ", "", "world\n"]), "hello world")
    }
}
