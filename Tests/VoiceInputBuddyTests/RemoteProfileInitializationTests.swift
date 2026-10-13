import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Remote profile initialization")
@MainActor
struct RemoteProfileInitializationTests {
    @Test func newInstallationHasNoInventedRemoteAndRegistrationPersists() throws {
        let suite = "remote-profile-initialization-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.remoteDeviceProfiles.isEmpty)
        #expect(settings.selectedRemoteProfileID == nil)
        settings.setAction(.commandCopy, for: .right)
        let device = UUID()
        let profile = settings.registerBluetoothRemote(identifier: device)
        settings.selectRemoteProfile(profile)
        #expect(settings.remoteDeviceProfiles.count == 1)
        #expect(settings.action(for: .right) == .commandCopy)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.remoteDeviceProfiles.count == 1)
        #expect(reloaded.selectedRemoteProfileID == profile)
        #expect(reloaded.profileID(forBluetoothIdentifier: device) == profile)
    }

    @Test func emptyOrCorruptProfileStorageDoesNotInventADevice() throws {
        for data in [Data("[]".utf8), Data("broken".utf8)] {
            let suite = "remote-profile-empty-" + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(data, forKey: AppSettings.Keys.remoteDeviceProfiles)
            defaults.set(UUID().uuidString, forKey: AppSettings.Keys.selectedRemoteProfileID)
            let settings = AppSettings(defaults: defaults)
            #expect(settings.remoteDeviceProfiles.isEmpty)
            #expect(settings.selectedRemoteProfileID == nil)
        }
    }
}
