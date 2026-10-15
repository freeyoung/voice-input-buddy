import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func enablePhoneRemoteConnection() {
        guard started, !isPhoneRemoteConnectionEnabled else { return }
        guard OnboardingBuildCapabilities.availableControlSources.contains(.appleCompanion) else {
            objectWillChange.send()
            return
        }
        isPhoneRemoteConnectionEnabled = true
        AppLogger.shared.write("PHONE REMOTE enabled_by_user")
    }

    func disablePhoneRemoteConnection() {
        guard isPhoneRemoteConnectionEnabled else { return }
        isPhoneRemoteConnectionEnabled = false
        isPhoneRemoteConnected = false
        isWatchRemoteConnected = false
        cancelPhoneApproval()
        AppLogger.shared.write("PHONE REMOTE disabled_by_user")
    }

    func togglePhoneRemoteConnection() {
        if isPhoneRemoteConnectionEnabled {
            disablePhoneRemoteConnection()
        } else {
            enablePhoneRemoteConnection()
        }
    }

    var isWatchRemoteConnectionEnabled: Bool {
        isPhoneRemoteConnectionEnabled
    }

    func enableWatchRemoteConnection() {
        enablePhoneRemoteConnection()
    }

    func toggleWatchRemoteConnection() {
        togglePhoneRemoteConnection()
    }

    func enableWebRemoteConnection() {
        guard started else { return }
        webRemoteState = .unavailable
    }

    func disableWebRemoteConnection() {
        webRemoteState = .disabled
        AppLogger.shared.write(
            "WEB REMOTE SESSION phase=cancelled result=cancelled " +
                "reason=cancelled_by_user"
        )
    }

    @MainActor func updatePhoneRemoteButtonTitles(
        bindings: [RemoteButton: ButtonAction],
        shortcuts: [RemoteButton: CustomKeyboardShortcut],
        applicationProfileIDs: [RemoteButton: UUID] = [:],
        customApplicationProfiles: [CustomApplicationProfile] = [],
        localization: LocalizationStore
    ) {
        var titles: [String: String] = [:]
        for button in RemoteButton.allCases {
            let action = bindings[button] ?? .disabled
            guard action != AppSettings.defaultBindings[button] else { continue }
            let fullTitle: String
            if action == .customShortcut {
                fullTitle = shortcuts[button]?.displayName(using: localization)
                    ?? action.displayName(using: localization)
            } else if action == .openCustomApplication,
                      let profileID = applicationProfileIDs[button],
                      let profile = customApplicationProfiles.first(where: { $0.id == profileID })
            {
                fullTitle = profile.displayName
            } else {
                fullTitle = action.displayName(using: localization)
            }
            titles[button.rawValue] = String(fullTitle.prefix(10))
        }
        remoteButtonTitles = titles
    }
}
