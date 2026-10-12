import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteCore
import BuddyRemoteUI
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var bluetoothPermissionState: PermissionVisualState {
        bluetoothAuthorization == .allowedAlways ? .granted : .pending
    }

    func refreshPermissionStates() {
        bluetoothAuthorization = CBManager.authorization
        inputMonitoringGranted = HIDRemoteMonitor.isInputMonitoringGranted
        accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
    }

    func setCustomMappingEnabled(_ enabled: Bool) {
        refreshPermissionStates()
        settings.customMappingEnabled = enabled
        guard MappingPermissionPolicy.requiresPrompt(
            enabled: enabled,
            inputMonitoringGranted: inputMonitoringGranted,
            accessibilityGranted: accessibilityGranted
        ) else {
            isWaitingForMappingPermissions = false
            model.applyHIDSettings()
            return
        }
        isMappingPermissionAlertPresented = true
    }

    func resumeCustomMappingIfPermissionsGranted() {
        guard
            isWaitingForMappingPermissions,
            inputMonitoringGranted,
            accessibilityGranted
        else { return }
        isWaitingForMappingPermissions = false
        model.applyHIDSettings()
    }
}
