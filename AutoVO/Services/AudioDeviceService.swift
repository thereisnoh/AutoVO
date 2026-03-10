import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let uid: String
}

final class AudioDeviceService: ObservableObject {
    @Published private(set) var outputDevices: [AudioDevice] = []

    init() {
        refresh()
    }

    func refresh() {
        outputDevices = Self.enumerateOutputDevices()
    }

    private static func getCFStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ref)
        guard status == noErr, let value = ref?.takeRetainedValue() else { return nil }
        return value as String
    }

    static func enumerateOutputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize
        ) == noErr else { return [] }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs
        ) == noErr else { return [] }

        var result: [AudioDevice] = []

        for deviceID in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr,
                  streamSize >= MemoryLayout<AudioBufferList>.size else { continue }

            let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(streamSize),
                                                          alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { rawPtr.deallocate() }

            guard AudioObjectGetPropertyData(deviceID, &streamAddress, 0, nil, &streamSize, rawPtr) == noErr else { continue }

            let abl = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
            let bufferCount = Int(abl.pointee.mNumberBuffers)
            let buffersPtr = rawPtr.advanced(by: MemoryLayout<UInt32>.size).assumingMemoryBound(to: AudioBuffer.self)
            let totalChannels = (0..<bufferCount).reduce(0) { $0 + Int(buffersPtr[$1].mNumberChannels) }
            guard totalChannels > 0 else { continue }

            guard let name = getCFStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString),
                  let uid = getCFStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) else { continue }

            result.append(AudioDevice(id: deviceID, name: name, uid: uid))
        }

        return result
    }
}
