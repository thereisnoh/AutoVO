import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    @AppStorage("selectedVoiceIdentifier") var selectedVoiceIdentifier: String = ""
    @AppStorage("selectedAudioDeviceID") var selectedAudioDeviceIDRaw: Int = 0
    @AppStorage("speechRate") var speechRate: Double = 0.52
    /// Reopen the last project automatically at launch (when not launched via a file).
    @AppStorage("reopenLastProject") var reopenLastProject: Bool = true

    var selectedAudioDeviceID: UInt32? {
        get { selectedAudioDeviceIDRaw == 0 ? nil : UInt32(selectedAudioDeviceIDRaw) }
        set { selectedAudioDeviceIDRaw = newValue.map(Int.init) ?? 0 }
    }
}
