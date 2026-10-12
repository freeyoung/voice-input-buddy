import Combine
import Foundation

extension AppSettings {
    func recordLaunchAndDetectCompletedUpdate(
        currentBuild: String,
        sparkleHadLaunchedBefore: Bool
    ) -> Bool {
        let previousBuild = defaults.string(forKey: Keys.lastLaunchedBuild)
        let completedUpdate: Bool
        if
            let previousBuild,
            let previousBuildNumber = Int(previousBuild),
            let currentBuildNumber = Int(currentBuild)
        {
            completedUpdate = currentBuildNumber > previousBuildNumber
        } else {
            completedUpdate = previousBuild == nil && sparkleHadLaunchedBefore
        }

        if defaults.integer(forKey: Keys.onboardingMigrationVersion) < Self.currentOnboardingVersion {
            let hasPersistedOnboardingState =
                defaults.object(forKey: Keys.onboardingCompletedVersion) != nil ||
                defaults.object(forKey: Keys.onboardingStep) != nil ||
                defaults.object(forKey: Keys.onboardingRemoteAvailability) != nil ||
                defaults.object(forKey: Keys.onboardingControlMethod) != nil ||
                defaults.object(forKey: Keys.onboardingVoiceTool) != nil
            let isExistingInstall = hasPersistedAppConfiguration
            if !isOnboardingComplete, !hasPersistedOnboardingState, isExistingInstall {
                completeOnboarding()
            }
            defaults.set(Self.currentOnboardingVersion, forKey: Keys.onboardingMigrationVersion)
        }

        defaults.set(currentBuild, forKey: Keys.lastLaunchedBuild)
        return completedUpdate
    }

    private var hasPersistedAppConfiguration: Bool {
        [
            Keys.gainDB,
            Keys.selectedAudioDeviceUID,
            Keys.lastKnownAudioDeviceUID,
            Keys.customMappingEnabled,
            Keys.legacyExclusiveHID,
            Keys.buttonBindings,
            Keys.buttonShortcuts,
            Keys.buttonApplicationProfileIDs,
            Keys.secondaryButtonBindings,
            Keys.customApplicationProfiles,
            Keys.peripheralIdentifier,
            Keys.applicationLanguage,
            Keys.appIconIdentifier,
            Keys.voiceFnTapModeEnabled,
            Keys.voiceKeyMode,
            Keys.totalButtonPressCount,
            Keys.totalVoiceDuration,
            Keys.dailyStatistics,
            Keys.voiceSessionRanking,
            Keys.trustedPhoneIdentityFingerprints,
        ].contains { defaults.object(forKey: $0) != nil }
    }
}
