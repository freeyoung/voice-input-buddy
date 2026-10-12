import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

struct MobileRemoteButtonObservation: Equatable {
    let source: UsageEventSource
    let button: RemoteButton
}

enum BluetoothVoiceStopPolicy {
    /// Remote stop ends capture but must not discard PCM already scheduled for playback.
    static func shouldFlushAudio(handledByFnTapMode _: Bool) -> Bool {
        false
    }
}

enum VoiceKeyPendingDownPolicy {
    static func shouldRejectStart(
        streaming: Bool,
        pendingDown: Bool
    ) -> Bool {
        streaming && pendingDown
    }
}

enum VoiceKeySessionPreservationPolicy {
    static func shouldPreserveInputSourceSession(
        latchHeld: Bool,
        heldMode: VoiceKeyMode?,
        pendingMode: VoiceKeyMode?
    ) -> Bool {
        (latchHeld && heldMode?.requiresAccessibility == true) ||
            pendingMode?.requiresAccessibility == true
    }
}
