import Foundation
import CoreAudio

struct Project: Codable, Equatable {
    var scripts: [Script] = []
    var selectedVoiceIdentifier: String?
    /// Persistent CoreAudio device UID (nil = System Default). Numeric AudioDeviceIDs
    /// change across reboots and machines, so they are never written.
    var selectedAudioDeviceUID: String?

    init(scripts: [Script] = [], selectedVoiceIdentifier: String? = nil, selectedAudioDeviceUID: String? = nil) {
        self.scripts = scripts
        self.selectedVoiceIdentifier = selectedVoiceIdentifier
        self.selectedAudioDeviceUID = selectedAudioDeviceUID
    }

    // MARK: - Codable (with legacy migration)

    private enum CodingKeys: String, CodingKey {
        case scripts, selectedVoiceIdentifier, selectedAudioDeviceUID
        /// Legacy numeric device ID. Read for best-effort migration, never written.
        case selectedAudioDeviceID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scripts = try c.decodeIfPresent([Script].self, forKey: .scripts) ?? []
        selectedVoiceIdentifier = try c.decodeIfPresent(String.self, forKey: .selectedVoiceIdentifier)
        var uid = try c.decodeIfPresent(String.self, forKey: .selectedAudioDeviceUID)
        // Older files stored the per-boot numeric ID. If that device happens to be
        // present under the same ID right now, carry its UID over; otherwise the
        // project falls back to System Default and will store a UID on next save.
        if uid == nil, let legacyID = try c.decodeIfPresent(UInt32.self, forKey: .selectedAudioDeviceID) {
            uid = AudioDeviceService.uid(forDeviceID: AudioDeviceID(legacyID))
        }
        selectedAudioDeviceUID = uid
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scripts, forKey: .scripts)
        try c.encodeIfPresent(selectedVoiceIdentifier, forKey: .selectedVoiceIdentifier)
        try c.encodeIfPresent(selectedAudioDeviceUID, forKey: .selectedAudioDeviceUID)
    }
}

struct ProjectFile: Codable {
    /// Bump when the on-disk format changes incompatibly. Files newer than this are refused.
    static let currentVersion = 1

    let version: Int
    var project: Project

    init(project: Project) {
        self.version = Self.currentVersion
        self.project = project
    }
}
