import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Integration audio status")
@MainActor
struct IntegrationAudioStatusTests {
    @Test func integrationDestinationSurvivesIdleEngineAndDetectsMissingDriver() throws {
        let name = UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: values))
        model.audioDevices = [AudioDeviceInfo(id: 111, uid: DoubaoAudioDevicePolicy.deviceUID,
            name: DoubaoAudioDevicePolicy.deviceName)]
        #expect(model.audioStatus.key == "audio.output.none_selected")
        #expect(!model.isAudioOutputReady)
        #expect(model.integrationAudioDeviceStatus.key == "audio.compatibility.device_detected")
        model.audio.startupPending = true
        #expect(model.integrationAudioDeviceStatus.key == "audio.compatibility.checking")
        model.audio.startupPending = false
        model.audioDevices = []
        #expect(model.integrationAudioDeviceStatus.key == "audio.compatibility.device_not_detected")
        #expect(model.settings.selectedAudioDeviceUID == DoubaoAudioDevicePolicy.deviceUID)
    }
}
