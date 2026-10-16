import AppKit
import Combine
import CoreBluetooth
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var permissionsPage: some View {
        settingsPage {
            PageHeader(title: localization.text("settings.permissions.page_title"))
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text("settings.permissions.introduction")
                    .foregroundStyle(.secondary)
                GlassPanel { inlinePermissionsSection }
                microphoneDriverPanel
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("settings.permissions.privacy_title", systemImage: "lock.shield")
                            .font(.headline)
                        Text("settings.permissions.privacy_detail")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear {
            refreshPermissionStates()
            model.refreshAudioDevices()
        }
    }

    private var microphoneDriverPanel: some View {
        let installed = model.audioDevices.contains {
            OnboardingAudioSelectionPolicy.isSupportedDevice(uid: $0.uid, name: $0.name)
        }
        return GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("settings.driver.title", systemImage: "mic.fill").font(.headline)
                        Text("settings.driver.detail").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("audio.action.refresh_devices") { model.refreshAudioDevices() }
                        .compatibilityButtonStyle(.standard)
                }
                HStack {
                    Label(installed ? "settings.driver.installed" : "settings.driver.missing",
                          systemImage: installed ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(installed ? Color.green : Color.orange)
                    Spacer()
                    Button("audio.compatibility.open_install_guide") {
                        model.openDoubaoDriverInstructions(using: localization)
                    }
                    .compatibilityButtonStyle(.standard)
                }
                Label(DoubaoAudioDevicePolicy.deviceName, systemImage: "waveform")
                    .font(.subheadline)
                Text("settings.driver.fixed_output_help")
                    .font(.caption).foregroundStyle(.secondary)
                Text("settings.driver.reload_help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
