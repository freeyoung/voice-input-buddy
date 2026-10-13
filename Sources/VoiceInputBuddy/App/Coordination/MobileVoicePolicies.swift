import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

enum MobileVoiceSource: Equatable {
    case nearbyPhone
    case nearbyWatch
    case web

    var logName: String {
        switch self {
        case .nearbyPhone: return "iphone"
        case .nearbyWatch: return "watch"
        case .web: return "web"
        }
    }
}

enum MobileVoiceStartDisposition: Equatable {
    case startNow
    case deferUntilStopped
    case busy
}

enum MobileVoiceRestartPolicy {
    static func startDisposition(
        requested: MobileVoiceSource,
        active: MobileVoiceSource?,
        stopping: MobileVoiceSource?
    ) -> MobileVoiceStartDisposition {
        guard let active else { return .startNow }
        if active == requested, stopping == requested { return .deferUntilStopped }
        return .busy
    }

    static func shouldCancelPendingRestart(
        stopped: MobileVoiceSource,
        pending: MobileVoiceSource?
    ) -> Bool {
        pending == stopped
    }
}

enum MobileVoiceWatchRecoveryPolicy {
    static let noAudioTimeout: TimeInterval = 5

    static func shouldRecover(
        startedAt: Date,
        now: Date,
        receivedBatchCount: Int
    ) -> Bool {
        receivedBatchCount == 0 &&
            now.timeIntervalSince(startedAt) >= noAudioTimeout
    }
}

enum MobileVoiceStopDisposition: Equatable {
    case ignoredInactive
    case ignoredAlreadyStopping(cancelledPendingRestart: Bool)
    case begin(generation: UInt64)
}

enum MobileVoiceStopCompletion: Equatable {
    case ignored
    case stopped
    case restart(MobileVoiceSource)
}

struct MobileVoiceLifecycleState {
    private(set) var activeSource: MobileVoiceSource?
    private(set) var stoppingSource: MobileVoiceSource?
    private(set) var pendingRestartSource: MobileVoiceSource?
    private(set) var stopGeneration: UInt64 = 0

    mutating func markStarted(_ source: MobileVoiceSource) {
        activeSource = source
    }

    mutating func requestStart(_ source: MobileVoiceSource) -> MobileVoiceStartDisposition {
        let disposition = MobileVoiceRestartPolicy.startDisposition(
            requested: source,
            active: activeSource,
            stopping: stoppingSource
        )
        guard disposition == .deferUntilStopped else { return disposition }
        guard pendingRestartSource == nil else { return .busy }
        pendingRestartSource = source
        return disposition
    }

    mutating func beginStop(_ source: MobileVoiceSource) -> MobileVoiceStopDisposition {
        guard activeSource == source else { return .ignoredInactive }
        guard stoppingSource != source else {
            let cancelledPendingRestart = MobileVoiceRestartPolicy.shouldCancelPendingRestart(
                stopped: source,
                pending: pendingRestartSource
            )
            if cancelledPendingRestart {
                pendingRestartSource = nil
            }
            return .ignoredAlreadyStopping(
                cancelledPendingRestart: cancelledPendingRestart
            )
        }
        stoppingSource = source
        stopGeneration &+= 1
        return .begin(generation: stopGeneration)
    }

    mutating func completeStop(
        _ source: MobileVoiceSource,
        generation: UInt64
    ) -> MobileVoiceStopCompletion {
        guard stopGeneration == generation,
              activeSource == source,
              stoppingSource == source
        else { return .ignored }
        activeSource = nil
        stoppingSource = nil
        guard pendingRestartSource == source else { return .stopped }
        pendingRestartSource = nil
        return .restart(source)
    }

    @discardableResult
    mutating func reset() -> Bool {
        stopGeneration &+= 1
        let cancelledPendingRestart = pendingRestartSource != nil
        activeSource = nil
        stoppingSource = nil
        pendingRestartSource = nil
        return cancelledPendingRestart
    }
}

struct MobileButtonGestureKey: Hashable {
    let source: RemoteInputSource
    let button: RemoteButton
}

struct AppleRemoteButtonGestureKey: Hashable {
    let device: SiriRemoteDeviceIdentity
    let button: RemoteButton
}

/// Discovery events without an identity never own an active voice session.
enum BluetoothVoiceDeviceOwnershipPolicy {
    static func matches(_ identifier: UUID?, active: UUID?) -> Bool {
        guard let identifier else { return false }
        return identifier == active
    }
}
