import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func requestPhoneApproval(
        deviceName: String,
        pairingCode: String,
        identityFingerprint: String?,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            guard self.isPhoneRemoteConnectionEnabled else {
                completion(false)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            let localization = LocalizationStore(settings: self.settings)
            let alert = NSAlert()
            alert.messageText = LocalizedMessage(
                "connection.approval.title", arguments: [deviceName]
            ).text(using: localization)
            alert.icon = NSApp.applicationIconImage
            if Self.isAppleWatchDeviceName(deviceName) {
                alert.informativeText = localization.text("connection.approval.watch_body")
            } else {
                alert.informativeText = localization.text("connection.approval.phone_body")
            }
            let codeLabel = NSTextField(labelWithString: pairingCode.map(String.init).joined(separator: " "))
            codeLabel.frame = NSRect(x: 0, y: 0, width: 300, height: 44)
            codeLabel.alignment = .center
            codeLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
            codeLabel.textColor = .controlAccentColor
            codeLabel.setAccessibilityLabel(LocalizedMessage(
                "connection.approval.code_accessibility", arguments: [pairingCode]
            ).text(using: localization))
            alert.accessoryView = codeLabel
            alert.addButton(withTitle: localization.text("connection.approval.allow"))
            alert.addButton(withTitle: localization.text("connection.approval.deny"))
            alert.addButton(withTitle: localization.text("connection.phone.cancel_waiting"))
            self.phoneApprovalAlert = alert
            let response = alert.runModal()
            guard self.phoneApprovalAlert === alert else {
                completion(false)
                return
            }
            self.phoneApprovalAlert = nil
            if response == .alertThirdButtonReturn {
                completion(false)
                self.disablePhoneRemoteConnection()
                return
            }
            let allowed = response == .alertFirstButtonReturn
            if allowed, let identityFingerprint {
                self.settings.trustPhoneIdentity(identityFingerprint)
            }
            completion(allowed)
        }
    }

    func cancelPhoneApproval() {
        DispatchQueue.main.async {
            guard let alert = self.phoneApprovalAlert else { return }
            self.phoneApprovalAlert = nil
            NSApp.abortModal()
            alert.window.orderOut(nil)
        }
    }

    func requestWebApproval(
        deviceName: String,
        pairingCode: String,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let localization = LocalizationStore(settings: self.settings)
            let alert = NSAlert()
            alert.messageText = LocalizedMessage(
                "connection.approval.web_title", arguments: [deviceName]
            ).text(using: localization)
            alert.informativeText = localization.text("connection.approval.web_body")
            alert.icon = NSApp.applicationIconImage
            let codeLabel = NSTextField(
                labelWithString: pairingCode.map(String.init).joined(separator: " ")
            )
            codeLabel.frame = NSRect(x: 0, y: 0, width: 300, height: 44)
            codeLabel.alignment = .center
            codeLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
            codeLabel.textColor = .controlAccentColor
            codeLabel.setAccessibilityLabel(LocalizedMessage(
                "connection.approval.code_accessibility", arguments: [pairingCode]
            ).text(using: localization))
            alert.accessoryView = codeLabel
            alert.addButton(withTitle: localization.text("connection.approval.allow"))
            alert.addButton(withTitle: localization.text("connection.approval.deny"))
            self.webApprovalAlert = alert
            let allowed = alert.runModal() == .alertFirstButtonReturn
            guard self.webApprovalAlert === alert else {
                completion(false)
                return
            }
            self.webApprovalAlert = nil
            completion(allowed)
        }
    }

    func cancelWebApproval() {
        DispatchQueue.main.async {
            guard let alert = self.webApprovalAlert else { return }
            self.webApprovalAlert = nil
            NSApp.abortModal()
            alert.window.orderOut(nil)
        }
    }

    nonisolated static func appRemoteButton(rawValue: String) -> RemoteButton? {
        RemoteButton(rawValue: rawValue)
    }

    nonisolated static func appRemoteButtonPhase(rawValue: String) -> RemoteButtonPhase? {
        RemoteButtonPhase(rawValue: rawValue)
    }

    nonisolated static func isAppleWatchDeviceName(_ deviceName: String) -> Bool {
        deviceName.range(of: "watch", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
