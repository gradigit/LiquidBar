import Foundation
import CoreAudio

/// Minimal CoreAudio wrapper for adjusting system output volume.
///
/// Kept isolated because audio device volume support varies by device.
enum SystemAudioService {
    static func changeOutputVolume(delta: Float) {
        guard let current = getOutputVolume() else { return }
        let next = max(0, min(1, current + delta))
        _ = setOutputVolume(next)
    }

    static func getOutputVolume() -> Float? {
        guard let deviceId = defaultOutputDeviceId() else { return nil }

        // Fall back to channel 1/2 average.
        let left = getScalarProperty(
            objectId: deviceId,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: 1
        )
        let right = getScalarProperty(
            objectId: deviceId,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: 2
        )
        switch (left, right) {
        case let (l?, r?): return (l + r) * 0.5
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    static func setOutputVolume(_ volume: Float) -> Bool {
        let clamped = max(0, min(1, volume))
        guard let deviceId = defaultOutputDeviceId() else { return false }

        // Fall back to channel 1/2.
        let lOk = setScalarProperty(
            objectId: deviceId,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: 1,
            value: clamped
        )
        let rOk = setScalarProperty(
            objectId: deviceId,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput,
            element: 2,
            value: clamped
        )
        return lOk || rOk
    }

    // MARK: - CoreAudio Helpers

    private static func defaultOutputDeviceId() -> AudioObjectID? {
        var deviceId = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &deviceId
        )
        guard status == noErr, deviceId != 0 else { return nil }
        return deviceId
    }

    private static func getScalarProperty(
        objectId: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(objectId, &addr) else { return nil }

        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(objectId, &addr, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return Float(value)
    }

    private static func setScalarProperty(
        objectId: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        value: Float
    ) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(objectId, &addr) else { return false }

        var mutable = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(objectId, &addr, 0, nil, size, &mutable)
        return status == noErr
    }
}
