import Foundation

struct Project: Codable {
    var scripts: [Script] = []
    var selectedVoiceIdentifier: String?
    var selectedAudioDeviceID: UInt32?
}

struct ProjectFile: Codable {
    let version: Int
    var project: Project

    init(project: Project) {
        self.version = 1
        self.project = project
    }
}
