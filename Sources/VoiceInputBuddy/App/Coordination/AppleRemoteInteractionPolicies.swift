import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

enum AppleRemoteInteractionPolicy {
    static func repeatIntervalMilliseconds(
        for button: RemoteButton,
        action: ButtonAction,
        hasSecondaryAction: Bool,
        hasSingleActionOverride: Bool,
        frontmostBundleIdentifier: String?
    ) -> UInt64? {
        guard !hasSecondaryAction,
              !hasSingleActionOverride,
              action != .disabled,
              action != .appSwitcher,
              HIDRemoteMonitor.shouldRepeat(
                  action: action,
                  frontmostBundleIdentifier: frontmostBundleIdentifier
              )
        else { return nil }
        return HIDRemoteTiming.repeatIntervalMilliseconds(for: button)
    }

    static func blocksTouch(activeVoiceDeviceCount: Int, voiceStopping: Bool) -> Bool {
        activeVoiceDeviceCount > 0 || voiceStopping
    }
}

struct AppleRemoteCircularNavigationAccumulator {
    static let stepThreshold = 18.0
    static let maximumStepsPerEvent = 3

    private(set) var pendingPixels = 0.0

    mutating func consume(_ pixels: Double) -> Int {
        guard pixels != 0 else { return 0 }
        if pendingPixels != 0, pendingPixels.sign != pixels.sign {
            pendingPixels = 0
        }
        pendingPixels += pixels
        let availableSteps = Int(abs(pendingPixels) / Self.stepThreshold)
        guard availableSteps > 0 else { return 0 }

        let emittedSteps = min(availableSteps, Self.maximumStepsPerEvent)
        let direction = pendingPixels > 0 ? 1 : -1
        pendingPixels -= Double(direction * emittedSteps) * Self.stepThreshold
        return direction * emittedSteps
    }

    mutating func reset() {
        pendingPixels = 0
    }

    static func movesLeft(for steps: Int) -> Bool {
        // The Siri Remote click-wheel contract emits negative pixels clockwise
        // and positive pixels counter-clockwise.
        steps > 0
    }
}
