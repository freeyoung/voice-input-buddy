import Foundation

enum DoubaoAudioDevicePolicy {
    static let deviceUID = "BuddyMic2ch_UID"
    static let deviceName = "Voice Input Buddy Mic"
    static let legacyDeviceName = "Voice Input Buddy"

    static func device(in devices: [AudioDeviceInfo]) -> AudioDeviceInfo? {
        // Prefer the stable UID, even if a physical device has the same name.
        devices.first { $0.uid == deviceUID }
            ?? devices.first { $0.name == legacyDeviceName }
    }

    static func status(in devices: [AudioDeviceInfo]) -> LocalizedMessage {
        if let device = device(in: devices) {
            return LocalizedMessage("audio.compatibility.device_detected", arguments: [device.name])
        }
        return LocalizedMessage("audio.compatibility.device_not_detected", arguments: [deviceName])
    }
}
