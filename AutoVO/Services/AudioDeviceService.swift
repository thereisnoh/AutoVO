import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let uid: String
}

final class AudioDeviceService: ObservableObject {
    @Published private(set) var outputDevices: [AudioDevice] = []

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refresh()
        addListeners()
    }

    deinit {
        removeListeners()
    }

    func refresh() {
        outputDevices = Self.enumerateOutputDevices()
    }

    // MARK: - Hot-plug listening

    private static let monitoredSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,             // device added / removed
        kAudioHardwarePropertyDefaultOutputDevice  // default output changed
    ]

    private static func systemAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private func addListeners() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh()   // delivered on .main (the queue passed below)
        }
        listenerBlock = block
        for selector in Self.monitoredSelectors {
            var address = Self.systemAddress(selector)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
    }

    private func removeListeners() {
        guard let block = listenerBlock else { return }
        for selector in Self.monitoredSelectors {
            var address = Self.systemAddress(selector)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
        listenerBlock = nil
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

    /// Read a UInt32 device property, or nil if it can't be read.
    private static func getUInt32Property(deviceID: AudioDeviceID,
                                          selector: AudioObjectPropertySelector,
                                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
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

            // Use UnsafeMutableAudioBufferListPointer for correct struct layout:
            // `mBuffers` is 8-byte aligned (offset 8, not 4), so manually advancing
            // by sizeof(UInt32) reads mNumberChannels out of padding → always 0,
            // which silently filtered out every real output device.
            let abl = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
            let bufferList = UnsafeMutableAudioBufferListPointer(abl)
            let totalChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard totalChannels > 0 else { continue }

            // Skip devices that aren't real picker candidates. The app's own
            // AVAudioEngine spawns a private aggregate when it switches output
            // devices; such aggregates are flagged hidden and/or can't be the
            // default device. (A failed read is treated as "include" so we never
            // over-filter a legitimate device.)
            if let hidden = getUInt32Property(deviceID: deviceID, selector: kAudioDevicePropertyIsHidden),
               hidden != 0 { continue }
            if let canBeDefault = getUInt32Property(deviceID: deviceID,
                                                    selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                                                    scope: kAudioObjectPropertyScopeOutput),
               canBeDefault == 0 { continue }

            guard let name = getCFStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString),
                  let uid = getCFStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) else { continue }

            result.append(AudioDevice(id: deviceID, name: name, uid: uid))
        }

        return result
    }
}
