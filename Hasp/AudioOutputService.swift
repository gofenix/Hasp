import CoreAudio
import Foundation

struct ListedOutput: Equatable, Sendable {
    var uid: String
    var name: String
    var transport: UInt32
    var isCurrent: Bool
}

enum AudioOutputService {
    static func outputs() -> [ListedOutput] {
        let current = currentOutputID()
        return outputDeviceIDs().compactMap { device in
            guard !isHidden(device) else { return nil }
            let name = deviceName(device)
            let uid = deviceUID(device)
            guard !name.isEmpty, !uid.isEmpty else { return nil }
            return ListedOutput(
                uid: uid,
                name: name,
                transport: transportType(device),
                isCurrent: device == current
            )
        }
    }

    static func select(uid: String) -> Bool {
        guard let device = outputDeviceIDs().first(where: { deviceUID($0) == uid }) else { return false }
        return setDefaultOutput(device) && currentOutputID() == device
    }

    static func volumeDescription() -> String? {
        let device = currentOutputID()
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &muted) == noErr && muted != 0 { return "已静音" }
        var volume: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &property, 0, nil, &size, &volume) == noErr {
            return "音量 \(Int((max(0, min(1, volume)) * 100).rounded()))%"
        }
        let name = deviceName(device)
        return name.isEmpty ? nil : name
    }

    static func startWatching(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        watch.lock.lock()
        watch.callbacks.append(onChange)
        let shouldInstall = !watch.installed
        watch.installed = true
        watch.lock.unlock()
        if shouldInstall {
            installWatchers()
        }
    }

    private static func installWatchers() {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            let callbacks = watch.snapshot()
            MainActor.assumeIsolated { callbacks.forEach { $0() } }
        }
        watch.lock.lock()
        watch.block = block
        watch.lock.unlock()
        let system = AudioObjectID(kAudioObjectSystemObject)
        var devices = address(kAudioHardwarePropertyDevices)
        var current = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(system, &devices, .main, block)
        AudioObjectAddPropertyListenerBlock(system, &current, .main, block)
    }

    private static func currentOutputID() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr else {
            return 0
        }
        return device
    }

    private static func outputDeviceIDs() -> [AudioDeviceID] {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter(hasOutput)
    }

    private static func hasOutput(_ device: AudioDeviceID) -> Bool {
        var property = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr && size > 0
    }

    private static func isHidden(_ device: AudioDeviceID) -> Bool {
        switch transportType(device) {
        case kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeHDMI:
            return true
        default:
            return false
        }
    }

    private static func transportType(_ device: AudioDeviceID) -> UInt32 {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var property = address(kAudioDevicePropertyTransportType)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &transport) == noErr else { return 0 }
        return transport
    }

    private static func deviceName(_ device: AudioDeviceID) -> String {
        stringProperty(device, selector: kAudioDevicePropertyDeviceNameCFString)
    }

    private static func deviceUID(_ device: AudioDeviceID) -> String {
        stringProperty(device, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func stringProperty(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var property = address(selector)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &name) == noErr,
              let name else { return "" }
        return name.takeRetainedValue() as String
    }

    private static func setDefaultOutput(_ device: AudioDeviceID) -> Bool {
        var device = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, size, &device) == noErr
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static let watch = WatchBox()

    /// All mutable fields are accessed under lock; callbacks run only on main.
    private final class WatchBox: @unchecked Sendable {
        let lock = NSLock()
        var callbacks: [@MainActor @Sendable () -> Void] = []
        var installed = false
        var block: AudioObjectPropertyListenerBlock?

        func snapshot() -> [@MainActor @Sendable () -> Void] {
            lock.lock()
            defer { lock.unlock() }
            return callbacks
        }
    }
}
