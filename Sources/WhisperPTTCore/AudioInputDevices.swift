import AVFoundation
import CoreAudio

public struct AudioInputDevice: Equatable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String

    public init(id: AudioDeviceID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

public enum AudioInputDevices {
    public static func available() throws -> [AudioInputDevice] {
        let devices = try ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        return devices.compactMap { id in
            guard let streams = try? ids(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput),
                  !streams.isEmpty,
                  let uid = try? string(id, kAudioDevicePropertyDeviceUID),
                  let name = try? string(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func defaultID() throws -> AudioDeviceID {
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id))
        return id
    }

    public static func resolve(_ uid: String?, devices: [AudioInputDevice], defaultID: AudioDeviceID) throws -> AudioInputDevice {
        if let uid {
            guard let device = devices.first(where: { $0.uid == uid }) else {
                throw failure("Selected microphone is unavailable. Reconnect it or choose another audio input.")
            }
            return device
        }
        guard let device = devices.first(where: { $0.id == defaultID }) else {
            throw failure("No system default microphone is available. Choose an audio input.")
        }
        return device
    }

    /// Changes only this engine's input, without changing the system's default device.
    @discardableResult
    public static func select(_ uid: String?, on input: AVAudioInputNode) throws -> AudioInputDevice {
        let device = try resolve(uid, devices: available(), defaultID: defaultID())
        try input.auAudioUnit.setDeviceID(device.id)
        guard input.auAudioUnit.deviceID == device.id else {
            throw failure("The microphone could not be selected. Please choose another audio input.")
        }
        return device
    }

    fileprivate static func address(_ selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    fileprivate static func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "WhisperPTTAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size))
        guard size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try values.withUnsafeMutableBytes { buffer in
            try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!))
        }
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
        guard let value else { throw failure("Could not read microphone information.") }
        return value.takeRetainedValue() as String
    }
}

public final class AudioInputMonitor {
    private let listener: AudioObjectPropertyListenerBlock
    private var addresses: [AudioObjectPropertyAddress] = []

    public init(onChange: @escaping @Sendable () -> Void) throws {
        listener = { _, _ in onChange() }
        do {
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
                var address = AudioInputDevices.address(selector)
                try AudioInputDevices.check(AudioObjectAddPropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &address, .main, listener
                ))
                addresses.append(address)
            }
        } catch {
            removeListeners()
            throw error
        }
    }

    deinit { removeListeners() }

    private func removeListeners() {
        for var address in addresses {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        addresses.removeAll()
    }
}
