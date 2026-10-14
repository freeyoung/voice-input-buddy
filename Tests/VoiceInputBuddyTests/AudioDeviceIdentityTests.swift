import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Virtual microphone identity")
struct AudioDeviceIdentityTests {
    @Test(arguments: ["Voice Input Buddy", "Voice Input Buddy Mic", "BlackHole 2ch"])
    func matchingNameDoesNotProveDriverIsInstalled(name: String) {
        let foreign = AudioDeviceInfo(id: 1, uid: "unrelated-output", name: name)
        #expect(DoubaoAudioDevicePolicy.device(in: [foreign]) == nil)
        #expect(!OnboardingAudioSelectionPolicy.isSupportedDevice(uid: foreign.uid, name: foreign.name))
    }

    @Test func stableUIDRecognizesRenamedDrivers() {
        let owned = AudioDeviceInfo(id: 1, uid: DoubaoAudioDevicePolicy.deviceUID, name: "Renamed microphone")
        #expect(DoubaoAudioDevicePolicy.device(in: [owned])?.id == owned.id)
        #expect(OnboardingAudioSelectionPolicy.isSupportedDevice(uid: owned.uid, name: owned.name))
        #expect(!OnboardingAudioSelectionPolicy.isSupportedDevice(uid: "BlackHole2ch_UID", name: "Renamed BlackHole"))
    }
}
