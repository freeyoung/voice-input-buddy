import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func openLogFolder() {
        let logger = AppLogger.shared
        logger.write("LOGS opened_by_user")
        logger.flush()
        if FileManager.default.fileExists(atPath: logger.logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logger.logURL])
        } else {
            let localization = LocalizationStore(settings: settings)
            let alert = NSAlert()
            alert.messageText = localization.text("diagnostics.logs.open_failed")
            alert.informativeText = localization.text("diagnostics.logs.open_failed.detail")
            alert.runModal()
        }
    }

    func recordPublicDiagnosticEvent(
        operationID: String? = nil,
        component: String,
        action: String,
        phase: String,
        result: String,
        reason: String,
        source: String? = nil,
        remoteModelFamily: String? = nil,
        elapsedMS: Int? = nil,
        receivedSamples: Int? = nil,
        scheduledSamples: Int? = nil,
        playedSamples: Int? = nil,
        interruptedSamples: Int? = nil,
        pendingSamples: Int? = nil,
        failureCount: Int? = nil
    ) {
        // History, recordings and telemetry are not part of this product.
    }

    func recordVoiceSessionCompletion(
        operationID: String,
        source: String,
        remoteModelFamily: String?,
        startedAt: Date?,
        receivedSamples: Int,
        failureCount: Int,
        stopReason: String
    ) {
        let diagnostic = voiceAudioDeliveryDiagnostic
        let received = max(receivedSamples, diagnostic.receivedSamples)
        let scheduled = diagnostic.scheduledSamples
        let played = diagnostic.playedSamples
        let interrupted = diagnostic.interruptedSamples
        let pending = diagnostic.outputAtObservation.pendingSamples
        let totalFailures = max(failureCount, diagnostic.enqueueFailures)
        let failureReason: String?
        if received == 0 {
            failureReason = "no_samples"
        } else if totalFailures > 0 {
            failureReason = "audio_enqueue_failed"
        } else if interrupted > 0 {
            failureReason = "playback_interrupted"
        } else if pending > 0 || scheduled < received || played < received {
            failureReason = "audio_incomplete"
        } else {
            failureReason = nil
        }
        recordPublicDiagnosticEvent(
            operationID: operationID,
            component: "voice",
            action: "session",
            phase: failureReason == nil ? "completed" : "failed",
            result: failureReason == nil ? "passed" : "failed",
            reason: failureReason ?? Self.publicVoiceStopReason(stopReason),
            source: source,
            remoteModelFamily: remoteModelFamily,
            elapsedMS: startedAt.map { max(0, Int(Date().timeIntervalSince($0) * 1_000)) },
            receivedSamples: received,
            scheduledSamples: scheduled,
            playedSamples: played,
            interruptedSamples: interrupted,
            pendingSamples: pending,
            failureCount: totalFailures
        )
    }

    private static func publicVoiceStopReason(_ reason: String) -> String {
        let approvedReasons: Set<String> = [
            "released", "voice_stop", "voice_stopped", "hold_release",
            "toggle_second_tap", "host_stop", "cancelled.link_unavailable",
            "app_stop", "device_disconnected",
        ]
        return approvedReasons.contains(reason) ? reason : "session_stopped"
    }

    func sendDiagnosticLogs() {
        // History, recordings and telemetry are not part of this product.
    }

    func openProjectFolder() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        var candidate = executable.deletingLastPathComponent()
        if candidate.path.contains(".app/Contents/MacOS") {
            candidate.deleteLastPathComponent()
            candidate.deleteLastPathComponent()
            candidate.deleteLastPathComponent()
        }
        NSWorkspace.shared.open(candidate)
    }

    func openPrivacyPane(_ pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
