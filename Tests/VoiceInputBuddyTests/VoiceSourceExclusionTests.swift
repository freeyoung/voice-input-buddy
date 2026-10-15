import Foundation
import Testing
import BuddyRemoteCore
@testable import VoiceInputBuddy

@Suite("Voice source exclusion")
@MainActor
struct VoiceSourceExclusionTests {
    @Test func pendingActiveAndDrainingSourcesExcludeOtherTransports() throws {
        let name = "voice-exclusion-" + UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: values), initialAudioDevices: [])
        #expect(model.canAcceptNewVoiceSession(from: .bluetooth))
        model.bluetoothVoiceActive = true
        #expect(!model.canAcceptNewVoiceSession(from: .appleRemote))
        #expect(!model.canAcceptNewVoiceSession(from: .mobile))
        var result: RemoteVoiceStartResult?
        model.requestPhoneVoiceStart(source: .web) { result = $0 }
        #expect(result == .busy)
        model.bluetoothVoiceActive = false
        model.pendingBluetoothVoiceStart.begin(for: UUID())
        #expect(!model.canAcceptNewVoiceSession(from: .appleRemote))
        model.pendingBluetoothVoiceStart.cancel()
        model.appleRemoteVoiceStopping = true
        #expect(!model.canAcceptNewVoiceSession(from: .bluetooth))
        #expect(!model.canAcceptNewVoiceSession(from: .mobile))
        #expect(model.canAcceptNewVoiceSession(from: .appleRemote))
        model.appleRemoteVoiceStopping = false
        model.pendingMobileVoiceActivationSource = .web
        #expect(!model.canAcceptNewVoiceSession(from: .bluetooth))
        #expect(!model.canAcceptNewVoiceSession(from: .appleRemote))
        model.pendingMobileVoiceActivationSource = nil
        model.mobileVoiceLifecycle.markStarted(.web)
        #expect(!model.canAcceptNewVoiceSession(from: .bluetooth))
        _ = model.mobileVoiceLifecycle.reset()
        model.pendingVoiceKeyActivationOwner = .appleRemote
        #expect(!model.canAcceptNewVoiceSession(from: .bluetooth))
        #expect(!model.canAcceptNewVoiceSession(from: .mobile))
        model.pendingVoiceKeyActivationOwner = nil
        #expect(model.canAcceptNewVoiceSession(from: .bluetooth))
    }
}
