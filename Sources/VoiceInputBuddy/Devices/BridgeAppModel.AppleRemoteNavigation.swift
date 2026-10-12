import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func performAppleRemoteAppSwitcher(
        for button: RemoteButton,
        trigger: ButtonTrigger,
        profileID: UUID? = nil
    ) -> Bool {
        let wasActive = appleRemoteAppSwitcherSession.isActive
        if !wasActive {
            appleRemoteAppSwitcherProfileID = profileID
            beginAppleRemoteAppSwitcherDiagnostics()
        }
        let phase = wasActive ? "tab" : "start"
        appleRemoteAppSwitcherTabCount += 1
        let submitted = appleRemoteAppSwitcherSession.trigger()
        AppLogger.shared.write(
            "APPLE REMOTE APP SWITCHER " +
                "operation_id=\(appleRemoteAppSwitcherOperationLabel) phase=\(phase) " +
                "button=\(button.rawValue) trigger=\(trigger.rawValue) " +
                "is_active_before=\(wasActive) " +
                "is_active_after=\(appleRemoteAppSwitcherSession.isActive) " +
                "success=\(submitted)"
        )
        if submitted {
            if !wasActive {
                appleRemoteCircularNavigation.reset()
                siriRemoteFeature.setTouchRoutingMode(.circularNavigation)
                startAppleRemoteAppSwitcherLifecycle()
                AppLogger.shared.write(
                    "APPLE REMOTE TOUCH_CONTEXT " +
                        "operation_id=\(appleRemoteAppSwitcherOperationLabel) " +
                        "phase=started result=active " +
                        "context=app_switcher direction=clockwise_next"
                )
            }
            scheduleAppleRemoteAppSwitcherTimeout()
        } else if wasActive {
            finishAppleRemoteAppSwitcher(reason: "tab_failed", confirmed: false)
        } else {
            finishAppleRemoteAppSwitcher(reason: "start_failed", confirmed: false)
        }
        return submitted
    }

    private func handleAppleRemoteContextualScroll(_ pixels: Double) -> Bool {
        guard appleRemoteAppSwitcherSession.isActive else {
            AppLogger.shared.write(
                "APPLE REMOTE TOUCH_CONTEXT operation_id=none " +
                    "phase=ignored result=context_inactive " +
                    "context=app_switcher"
            )
            return false
        }

        let steps = appleRemoteCircularNavigation.consume(pixels)
        guard steps != 0 else {
            AppLogger.shared.write(
                "APPLE REMOTE TOUCH_CONTEXT " +
                    "operation_id=\(appleRemoteAppSwitcherOperationLabel) " +
                    "phase=accumulating result=pending " +
                    "context=app_switcher pixels=\(pixels)"
            )
            return true
        }

        let movesLeft = AppleRemoteCircularNavigationAccumulator.movesLeft(for: steps)
        appleRemoteAppSwitcherTouchNavigationSteps += abs(steps)
        for completedStep in 0..<abs(steps) {
            guard appleRemoteAppSwitcherSession.moveSelection(left: movesLeft) else {
                AppLogger.shared.write(
                    "APPLE REMOTE TOUCH_CONTEXT " +
                        "operation_id=\(appleRemoteAppSwitcherOperationLabel) " +
                        "phase=navigate result=failed " +
                        "context=app_switcher direction=\(movesLeft ? "left" : "right") " +
                        "completed_steps=\(completedStep) requested_steps=\(abs(steps))"
                )
                finishAppleRemoteAppSwitcher(
                    reason: "touch_navigate_failed",
                    confirmed: false
                )
                return false
            }
        }

        scheduleAppleRemoteAppSwitcherTimeout()
        AppLogger.shared.write(
            "APPLE REMOTE TOUCH_CONTEXT " +
                "operation_id=\(appleRemoteAppSwitcherOperationLabel) " +
                "phase=navigate result=submitted " +
                "context=app_switcher direction=\(movesLeft ? "left" : "right") " +
                "steps=\(abs(steps)) pixels=\(pixels)"
        )
        return true
    }

    func handleAppleRemoteAppSwitcherControlPress(
        _ button: RemoteButton
    ) -> Bool {
        switch button {
        case .ok:
            appleRemoteAppSwitcherButtonConfirmationCount += 1
            let confirmed = appleRemoteAppSwitcherSession.confirm()
            finishAppleRemoteAppSwitcher(
                reason: confirmed ? "confirmed" : "confirm_failed",
                confirmed: confirmed
            )
            return true
        case .back:
            finishAppleRemoteAppSwitcher(reason: "back", confirmed: false)
            return true
        case .left, .right:
            if button == .left {
                appleRemoteAppSwitcherButtonLeftCount += 1
            } else {
                appleRemoteAppSwitcherButtonRightCount += 1
            }
            let moved = appleRemoteAppSwitcherSession.moveSelection(left: button == .left)
            AppLogger.shared.write(
                "APPLE REMOTE APP SWITCHER " +
                    "operation_id=\(appleRemoteAppSwitcherOperationLabel) " +
                    "phase=navigate button=\(button.rawValue) " +
                    "direction=\(button == .left ? "left" : "right") success=\(moved)"
            )
            if moved {
                scheduleAppleRemoteAppSwitcherTimeout()
            } else {
                finishAppleRemoteAppSwitcher(reason: "navigate_failed", confirmed: false)
            }
            return true
        case .up, .down:
            AppLogger.shared.write(
                "APPLE REMOTE APP SWITCHER " +
                    "operation_id=\(appleRemoteAppSwitcherOperationLabel) " +
                    "phase=navigate button=\(button.rawValue) " +
                    "direction=unsupported success=true"
            )
            return true
        case .tv:
            return performAppleRemoteAppSwitcher(for: button, trigger: .singleClick)
        default:
            return false
        }
    }

    private func scheduleAppleRemoteAppSwitcherTimeout() {
        appleRemoteAppSwitcherTimeout?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(Int(HIDRemoteTiming.appSwitcherTimeoutMilliseconds))
        )
        timer.setEventHandler { [weak self] in
            self?.finishAppleRemoteAppSwitcher(reason: "timeout", confirmed: false)
        }
        appleRemoteAppSwitcherTimeout = timer
        timer.resume()
    }

    private func startAppleRemoteAppSwitcherLifecycle() {
        scheduleAppleRemoteAppSwitcherTimeout()
        appleRemoteAppSwitcherFrontmostMonitor?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(Int(HIDRemoteTiming.appSwitcherFrontmostPollMilliseconds)),
            repeating: .milliseconds(Int(HIDRemoteTiming.appSwitcherFrontmostPollMilliseconds))
        )
        timer.setEventHandler { [weak self] in
            guard let self,
                  self.appleRemoteAppSwitcherSession.isActive,
                  let origin = self.appleRemoteAppSwitcherOriginBundleIdentifier,
                  let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  current != origin
            else { return }
            self.finishAppleRemoteAppSwitcher(reason: "frontmost_changed", confirmed: false)
        }
        appleRemoteAppSwitcherFrontmostMonitor = timer
        timer.resume()
    }

    var appleRemoteAppSwitcherOperationLabel: String {
        appleRemoteAppSwitcherOperationID.map(String.init) ?? "none"
    }

    private func beginAppleRemoteAppSwitcherDiagnostics() {
        appleRemoteAppSwitcherOperationCounter &+= 1
        appleRemoteAppSwitcherOperationID = appleRemoteAppSwitcherOperationCounter
        appleRemoteAppSwitcherStartedUptime = ProcessInfo.processInfo.systemUptime
        appleRemoteAppSwitcherOriginBundleIdentifier =
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        appleRemoteAppSwitcherTabCount = 0
        appleRemoteAppSwitcherTouchNavigationSteps = 0
        appleRemoteAppSwitcherButtonLeftCount = 0
        appleRemoteAppSwitcherButtonRightCount = 0
        appleRemoteAppSwitcherTouchConfirmationCount = 0
        appleRemoteAppSwitcherButtonConfirmationCount = 0
    }

    private func appleRemoteAppSwitcherSummary() -> String {
        let elapsedMilliseconds = Int(
            max(
                0,
                (ProcessInfo.processInfo.systemUptime -
                    (appleRemoteAppSwitcherStartedUptime ?? ProcessInfo.processInfo.systemUptime)) * 1_000
            )
        )
        return "tab_count=\(appleRemoteAppSwitcherTabCount) " +
            "touch_navigation_steps=\(appleRemoteAppSwitcherTouchNavigationSteps) " +
            "button_left_count=\(appleRemoteAppSwitcherButtonLeftCount) " +
            "button_right_count=\(appleRemoteAppSwitcherButtonRightCount) " +
            "touch_confirmation_count=\(appleRemoteAppSwitcherTouchConfirmationCount) " +
            "button_confirmation_count=\(appleRemoteAppSwitcherButtonConfirmationCount) " +
            "elapsed_ms=\(elapsedMilliseconds)"
    }

    private func resetAppleRemoteAppSwitcherDiagnostics() {
        appleRemoteAppSwitcherProfileID = nil
        appleRemoteAppSwitcherOperationID = nil
        appleRemoteAppSwitcherStartedUptime = nil
        appleRemoteAppSwitcherOriginBundleIdentifier = nil
        appleRemoteAppSwitcherTabCount = 0
        appleRemoteAppSwitcherTouchNavigationSteps = 0
        appleRemoteAppSwitcherButtonLeftCount = 0
        appleRemoteAppSwitcherButtonRightCount = 0
        appleRemoteAppSwitcherTouchConfirmationCount = 0
        appleRemoteAppSwitcherButtonConfirmationCount = 0
    }

    private func appleRemoteAppSwitcherTerminalResult(
        reason: String,
        commandReleased: Bool
    ) -> String {
        guard commandReleased else { return "submission_failed" }
        if reason == "timeout" { return "timed_out" }
        if reason.contains("failed") { return "submission_failed" }
        if reason == "frontmost_changed" { return "diagnostic_unknown" }
        return "cancelled"
    }

    func finishAppleRemoteAppSwitcher(reason: String, confirmed: Bool) {
        let operationID = appleRemoteAppSwitcherOperationID.map(String.init)
        let origin = appleRemoteAppSwitcherOriginBundleIdentifier ?? "unknown"
        let summary = appleRemoteAppSwitcherSummary()
        let wasActive = appleRemoteAppSwitcherSession.isActive
        appleRemoteAppSwitcherTimeout?.cancel()
        appleRemoteAppSwitcherTimeout = nil
        appleRemoteAppSwitcherFrontmostMonitor?.cancel()
        appleRemoteAppSwitcherFrontmostMonitor = nil
        appleRemoteCircularNavigation.reset()
        siriRemoteFeature.setTouchRoutingMode(.standard)
        let releaseSubmitted: Bool
        if appleRemoteAppSwitcherSession.isActive {
            releaseSubmitted = appleRemoteAppSwitcherSession.cancel()
        } else {
            releaseSubmitted = true
        }
        let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        guard let operationID else {
            AppLogger.shared.write(
                "APPLE REMOTE APP SWITCHER operation_id=none " +
                    "phase=finish_ignored result=no_active_operation reason=\(reason) " +
                    "is_active_before=\(wasActive) " +
                    "is_active_after=\(appleRemoteAppSwitcherSession.isActive) " +
                    "command_release=\(releaseSubmitted)"
            )
            resetAppleRemoteAppSwitcherDiagnostics()
            return
        }
        AppLogger.shared.write(
            "APPLE REMOTE APP SWITCHER operation_id=\(operationID) " +
                "phase=ended reason=\(reason) confirmed=\(confirmed) " +
                "origin=\(origin) current=\(current) " +
                "is_active_before=\(wasActive) " +
                "is_active_after=\(appleRemoteAppSwitcherSession.isActive) " +
                "command_release=\(releaseSubmitted) \(summary)"
        )
        if confirmed {
            scheduleAppleRemoteAppSwitcherVisibilityProbe(
                operationID: operationID,
                origin: origin,
                summary: summary,
                probeIndex: 0,
                targetBundleIdentifier: nil
            )
        } else {
            let terminalResult = appleRemoteAppSwitcherTerminalResult(
                reason: reason,
                commandReleased: releaseSubmitted
            )
            AppLogger.shared.write(
                "APPLE REMOTE APP SWITCHER operation_id=\(operationID) " +
                    "phase=terminal terminal_result=\(terminalResult) " +
                    "reason=\(reason) \(summary)"
            )
        }
        resetAppleRemoteAppSwitcherDiagnostics()
    }

    private func scheduleAppleRemoteAppSwitcherVisibilityProbe(
        operationID: String,
        origin: String,
        summary: String,
        probeIndex: Int,
        targetBundleIdentifier: String?
    ) {
        let delays = HIDRemoteTiming.appSwitcherVisibilityProbeMilliseconds
        guard probeIndex < delays.count else { return }
        let delay = probeIndex == 0 ? delays[0] : delays[probeIndex] - delays[probeIndex - 1]
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Int(delay))
        ) { [weak self] in
            guard let self else { return }
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            let originIsKnown = origin != "unknown"
            let target = targetBundleIdentifier ?? (
                originIsKnown && frontmost != origin && frontmost != "unknown" ? frontmost : nil
            )
            let snapshot = target.map {
                KeyboardInjector.applicationVisibilitySnapshot(bundleIdentifier: $0)
            }
            let probeResult: String
            if target == nil {
                probeResult = "awaiting_target"
            } else if frontmost != target {
                probeResult = "frontmost_mismatch"
            } else if snapshot?.isUserVisible == true {
                probeResult = "visible"
            } else if snapshot?.isUserVisible == false {
                probeResult = "no_visible_window"
            } else {
                probeResult = "diagnostic_unknown"
            }
            AppLogger.shared.write(
                "APPLE REMOTE APP SWITCHER operation_id=\(operationID) " +
                    "phase=visibility_probe result=\(probeResult) " +
                    "probe_delay_ms=\(delays[probeIndex]) origin=\(origin) " +
                    "target_bundle=\(target ?? "unknown") frontmost_bundle=\(frontmost) " +
                    "process_active=\(self.optionalDiagnosticBool(snapshot?.processActive)) " +
                    "process_hidden=\(self.optionalDiagnosticBool(snapshot?.processHidden)) " +
                    "process_terminated=\(self.optionalDiagnosticBool(snapshot?.processTerminated)) " +
                    "activation_policy=\(snapshot?.activationPolicy ?? "unknown") " +
                    "ordinary_window_count=\(self.optionalDiagnosticInt(snapshot?.ordinaryWindowCount)) " +
                    "onscreen_window_count=\(self.optionalDiagnosticInt(snapshot?.onscreenWindowCount)) " +
                    "visible_window_area_positive=\(self.optionalDiagnosticBool(snapshot?.hasVisibleWindow)) " +
                    "user_visible=\(self.optionalDiagnosticBool(snapshot?.isUserVisible)) " +
                    "diagnostic_boundary=window_content_unavailable"
            )

            if probeIndex + 1 < delays.count {
                self.scheduleAppleRemoteAppSwitcherVisibilityProbe(
                    operationID: operationID,
                    origin: origin,
                    summary: summary,
                    probeIndex: probeIndex + 1,
                    targetBundleIdentifier: target
                )
                return
            }

            let terminalResult: String
            if !originIsKnown {
                terminalResult = "diagnostic_unknown"
            } else if target == nil {
                terminalResult = "frontmost_unchanged"
            } else if frontmost != target {
                terminalResult = "diagnostic_unknown"
            } else if snapshot?.isUserVisible == true {
                terminalResult = "visible_target_confirmed"
            } else if snapshot?.isUserVisible == false {
                terminalResult = "frontmost_changed_no_visible_window"
            } else {
                terminalResult = "diagnostic_unknown"
            }
            AppLogger.shared.write(
                "APPLE REMOTE APP SWITCHER operation_id=\(operationID) " +
                    "phase=terminal terminal_result=\(terminalResult) " +
                    "target_bundle=\(target ?? "unknown") frontmost_bundle=\(frontmost) " +
                    summary
            )
        }
    }

    func optionalDiagnosticBool(_ value: Bool?) -> String {
        value.map(String.init) ?? "unknown"
    }

    private func optionalDiagnosticInt(_ value: Int?) -> String {
        value.map(String.init) ?? "unknown"
    }

    func elapsedMilliseconds(since uptime: TimeInterval) -> Int {
        max(0, Int((ProcessInfo.processInfo.systemUptime - uptime) * 1_000))
    }
}
