import Foundation

struct Project: Codable {
    var scripts: [Script] = []
    var selectedVoiceIdentifier: String?
    var selectedAudioDeviceID: UInt32?
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
