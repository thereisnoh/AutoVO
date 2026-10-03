import Foundation
import SwiftUI
import CoreAudio

final class AppSettings: ObservableObject {
    @AppStorage("selectedVoiceIdentifier") var selectedVoiceIdentifier: String = ""
    /// Persistent CoreAudio device UID of the chosen output; "" means System Default.
    /// (Numeric AudioDeviceIDs are only stable within a boot, so they are never stored.)
    @AppStorage("selectedAudioDeviceUID") var selectedAudioDeviceUID: String = ""
    @AppStorage("speechRate") var speechRate: Double = 0.52
    /// Reopen the last project automatically at launch (when not launched via a file).
    @AppStorage("reopenLastProject") var reopenLastProject: Bool = true

    private static let legacyDeviceIDKey = "selectedAudioDeviceID"

    init() {
        Self.migrateLegacyDeviceID()
    }

    /// The chosen output as it is persisted in a project: nil for System Default.
    var selectedAudioDeviceUIDOrNil: String? {
        get { selectedAudioDeviceUID.isEmpty ? nil : selectedAudioDeviceUID }
        set { selectedAudioDeviceUID = newValue ?? "" }
    }

    /// The chosen output resolved to a live AudioDeviceID for the player. nil means
    /// System Default, either by choice or because the chosen device isn't present.
    var resolvedOutputDeviceID: AudioDeviceID? {
        guard let uid = selectedAudioDeviceUIDOrNil else { return nil }
        return AudioDeviceService.deviceID(forUID: uid)
    }

    /// One-time: earlier builds stored the numeric device ID. Translate it to a UID if
    /// that device is still around (same boot), then drop the old key either way.
    private static func migrateLegacyDeviceID() {
        let defaults = UserDefaults.standard
        let legacyID = defaults.integer(forKey: legacyDeviceIDKey)
        guard legacyID != 0 else { return }
        if defaults.string(forKey: "selectedAudioDeviceUID") == nil,
           let uid = AudioDeviceService.uid(forDeviceID: AudioDeviceID(legacyID)) {
            defaults.set(uid, forKey: "selectedAudioDeviceUID")
        }
        defaults.removeObject(forKey: legacyDeviceIDKey)
    }
}
