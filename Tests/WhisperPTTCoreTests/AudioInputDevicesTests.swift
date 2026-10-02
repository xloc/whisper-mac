import AVFoundation
import CoreAudio
import XCTest
@testable import WhisperPTTCore

final class AudioInputDevicesTests: XCTestCase {
    private let builtIn = AudioInputDevice(id: 10, uid: "built-in", name: "Built-in Microphone")
    private let usb = AudioInputDevice(id: 20, uid: "usb-microphone", name: "USB Microphone")

    func testSystemDefaultFollowsTheCurrentDefault() throws {
        let devices = [builtIn, usb]
        XCTAssertEqual(try AudioInputDevices.resolve(nil, devices: devices, defaultID: builtIn.id), builtIn)
        XCTAssertEqual(try AudioInputDevices.resolve(nil, devices: devices, defaultID: usb.id), usb)
    }

    func testSpecifiedMicrophoneIgnoresDefaultAndSurvivesChangedHardwareID() throws {
        XCTAssertEqual(try AudioInputDevices.resolve(usb.uid, devices: [builtIn, usb], defaultID: builtIn.id), usb)
        let reconnected = AudioInputDevice(id: 42, uid: usb.uid, name: usb.name)
        XCTAssertEqual(try AudioInputDevices.resolve(usb.uid, devices: [builtIn, reconnected], defaultID: 0), reconnected)
    }

    func testMissingSpecifiedMicrophoneDoesNotUseAnotherDevice() {
        XCTAssertThrowsError(try AudioInputDevices.resolve(usb.uid, devices: [builtIn], defaultID: builtIn.id)) {
            XCTAssertTrue($0.localizedDescription.contains("unavailable"))
        }
    }

    func testMissingSystemDefaultReportsAnError() {
        XCTAssertThrowsError(try AudioInputDevices.resolve(nil, devices: [usb], defaultID: 0))
        XCTAssertThrowsError(try AudioInputDevices.resolve(nil, devices: [], defaultID: builtIn.id))
    }

    @MainActor
    func testRealDeviceBindingWithoutRecordingWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["WHISPER_PTT_RUN_AUDIO_DEVICE_TESTS"] == "1" else {
            throw XCTSkip("Set WHISPER_PTT_RUN_AUDIO_DEVICE_TESTS=1 to check hardware binding without recording")
        }
        let devices = try AudioInputDevices.available()
        guard !devices.isEmpty else { throw XCTSkip("No input devices are available") }
        let systemDefault = try AudioInputDevices.defaultID()
        for uid in [nil] + devices.map({ Optional($0.uid) }) {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let expected = try AudioInputDevices.resolve(uid, devices: devices, defaultID: systemDefault)
            XCTAssertEqual(try AudioInputDevices.select(uid, on: input), expected)
            XCTAssertEqual(input.auAudioUnit.deviceID, expected.id)
            XCTAssertGreaterThan(input.outputFormat(forBus: 0).channelCount, 0)
            XCTAssertGreaterThan(input.outputFormat(forBus: 0).sampleRate, 0)
            XCTAssertFalse(engine.isRunning)
            XCTAssertEqual(try AudioInputDevices.defaultID(), systemDefault, "Selecting an app input changed the system default")
        }
    }
}
