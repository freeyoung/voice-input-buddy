import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteCore
import BuddyRemoteUI
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    private var connectionBadge: String {
        localization.text(model.isConnected ? "common.status.connected" : "common.status.connecting")
    }

    var webRemoteStatusText: String {
        switch model.webRemoteState {
        case .disabled:
            return localization.text("connection.web.disabled")
        case .unavailable:
            return localization.text("connection.web.unavailable")
        case .connecting:
            return localization.text("connection.web.connecting")
        case .waitingForPhone:
            return localization.text("connection.web.waiting_scan")
        case .membershipRequired, .plusRequired:
            return localization.text("connection.web.plus_required_title")
        case .awaitingApproval:
            return localization.text("connection.web.waiting_approval")
        case .connected:
            return localization.text("connection.web.connected")
        case .failed:
            return localization.text("connection.web.failed")
        }
    }

    var webRemoteStatusTint: Color {
        switch model.webRemoteState {
        case .connected:
            return .green
        case .failed, .unavailable, .membershipRequired, .plusRequired:
            return .orange
        default:
            return .secondary
        }
    }

    func requestWebRemoteSession() {
        openWebRemoteSession()
    }

    func copyRepositoryLink() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        isRepositoryLinkCopied = pasteboard.writeObjects([
            AppLinks.githubRepository.absoluteString as NSString
        ])
    }

    private func openWebRemoteSession() {
        if !model.webRemoteState.isEnabled {
            model.enableWebRemoteConnection()
        }
        guard model.webRemoteState.isEnabled else { return }
        isWebRemoteSessionPresented = true
    }

    var connectionTint: Color {
        model.isConnected ? .green : .orange
    }

    private var voiceTriggerBadge: String {
        localization.text(model.isVoiceTriggerEnabled ? "common.status.enabled" : "common.status.preparing")
    }
}
