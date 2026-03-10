import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    @AppStorage("selectedVoiceIdentifier") var selectedVoiceIdentifier: String = ""
    @AppStorage("selectedAudioDeviceID") var selectedAudioDeviceIDRaw: Int = 0

    var selectedAudioDeviceID: UInt32? {
        get { selectedAudioDeviceIDRaw == 0 ? nil : UInt32(selectedAudioDeviceIDRaw) }
        set { selectedAudioDeviceIDRaw = newValue.map(Int.init) ?? 0 }
    }
}
