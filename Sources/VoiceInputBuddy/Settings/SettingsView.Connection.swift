import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteCore
import BuddyRemoteUI
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var connectionPage: some View {
        settingsPage {
            PageHeader(title: localization.text("connection.page.title"))
        } content: {
            CompatibilityGlassContainer(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    connectionDevicePanel
                        .frame(width: 230)
                    VStack(spacing: 14) {
                        audioSettingsPanel
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .onAppear {
            model.refreshVoiceKeyCompatibilityWarning()
        }
    }

    func voiceKeyCompatibilityWarningPanel(
        _ warning: VoiceKeyCompatibilityWarning
    ) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("connection.voice_key_compatibility.title")
                        .font(.system(size: 13, weight: .semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                Text(LocalizedMessage(warning.messageKey).text(using: localization))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("connection.voice_key_compatibility.recheck") {
                    model.recheckRemoteInput()
                }
                .compatibilityButtonStyle(.standard)
            }
        }
    }

    private var connectionMembershipRequiredView: some View {
        membershipFeature.membershipRequiredView {
            selectedSection = .membership
            membershipFeature.refreshIfNeeded()
        }
    }

    private var phoneConnectionsPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("connection.phone.section_title")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("connection.phone.ios_title")
                                .font(.subheadline.weight(.semibold))
                            Text("connection.phone.ios_help")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                Link(destination: AppLinks.githubRepository) {
                                    Label("about.support.github", systemImage: "arrow.up.right.square")
                                }
                                .compatibilityButtonStyle(.standard)

                                Button {
                                    copyRepositoryLink()
                                } label: {
                                    Label(
                                        localization.text(
                                            isRepositoryLinkCopied
                                                ? "common.status.copied"
                                                : "common.action.copy_link"
                                        ),
                                        systemImage: isRepositoryLinkCopied ? "checkmark" : "doc.on.doc"
                                    )
                                }
                                .compatibilityButtonStyle(.standard)
                            }
                        }

                        Spacer(minLength: 8)

                        Text(localization.text(
                            model.isPhoneRemoteConnected
                                ? "connection.phone.connected"
                                : model.isPhoneRemoteConnectionEnabled
                                    ? "connection.phone.enabled"
                                    : "connection.phone.not_enabled"
                        ))
                        .font(.caption)
                        .foregroundStyle(model.isPhoneRemoteConnected
                            ? Color.green
                            : model.isPhoneRemoteConnectionEnabled ? .orange : .secondary)
                        .lineLimit(1)

                        if membershipFeature.canStartCompanionConnection {
                            Button(
                                model.isPhoneRemoteConnected
                                    ? "connection.phone.disconnect"
                                    : model.isPhoneRemoteConnectionEnabled
                                        ? "connection.phone.cancel_waiting"
                                        : "connection.phone.connect"
                            ) {
                                model.togglePhoneRemoteConnection()
                            }
                            .compatibilityButtonStyle(.standard)
                            .controlSize(.regular)
                        } else {
                            connectionMembershipRequiredView
                        }
                    }

                    if membershipFeature.canStartCompanionConnection, let invitation = model.phoneRemoteInvitation {
                        Divider()
                        PhoneRemoteInvitationCard(invitation: invitation)
                    }
                }

                Divider()

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("connection.watch.title")
                            .font(.subheadline.weight(.semibold))
                        Text("connection.watch.help")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(localization.text(
                        model.isWatchRemoteConnected
                            ? "connection.watch.connected"
                            : model.isWatchRemoteConnectionEnabled
                                ? "connection.watch.enabled"
                                : "connection.phone.not_enabled"
                    ))
                    .font(.caption)
                    .foregroundStyle(model.isWatchRemoteConnected
                        ? Color.green
                        : model.isWatchRemoteConnectionEnabled ? .orange : .secondary)
                    .lineLimit(1)

                    if membershipFeature.canStartCompanionConnection {
                        Button(
                            model.isWatchRemoteConnected
                                ? "connection.watch.disconnect"
                                : model.isWatchRemoteConnectionEnabled
                                    ? "connection.watch.cancel_waiting"
                                    : "connection.watch.connect"
                        ) {
                            model.toggleWatchRemoteConnection()
                        }
                        .compatibilityButtonStyle(.standard)
                        .controlSize(.regular)
                    } else {
                        connectionMembershipRequiredView
                    }
                }

                Divider()

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("connection.web.title")
                            .font(.subheadline.weight(.semibold))
                        Text("connection.web.help_short")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                    Text(webRemoteStatusText)
                        .font(.caption)
                        .foregroundStyle(webRemoteStatusTint)
                        .lineLimit(1)
                    if membershipFeature.canStartCompanionConnection || model.webRemoteState.isEnabled {
                        Button(
                            model.webRemoteState.isEnabled
                                ? "connection.web.show_qr"
                                : "connection.web.connect"
                        ) {
                            requestWebRemoteSession()
                        }
                        .compatibilityButtonStyle(.standard)
                        .controlSize(.regular)
                    } else {
                        connectionMembershipRequiredView
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Label(
                        LocalizedMessage(
                            "connection.trusted_devices.count_long",
                            arguments: [String(settings.trustedPhoneIdentityFingerprints.count)]
                        ).text(using: localization),
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("connection.trusted_devices.clear") {
                        isClearTrustedPhonesConfirmationPresented = true
                    }
                    .compatibilityButtonStyle(.standard)
                    .disabled(settings.trustedPhoneIdentityFingerprints.isEmpty)
                }
            }
        }
    }

    private var connectionDevicePanel: some View {
        GlassPanel {
            VStack(spacing: 16) {
                remoteDeviceSelector(vertical: true)

                connectionRemotePhoto

                VStack(alignment: .leading, spacing: 9) {
                    connectionStatusLine(
                        symbol: "antenna.radiowaves.left.and.right",
                        text: model.connectionStatus.text(using: localization),
                        tint: connectionTint
                    )
                    connectionStatusLine(
                        symbol: "waveform",
                        text: localization.text(
                            model.isStreaming
                                ? "connection.status.voice_streaming"
                                : "connection.status.voice_ready"
                        ),
                        tint: model.isStreaming ? .orange : .blue
                    )
                    connectionStatusLine(
                        symbol: "mic.fill",
                        text: model.voiceShortcutStatus.text(using: localization),
                        tint: .blue
                    )
                }

                Button {
                    model.reconnect()
                } label: {
                    Text("connection.action.reconnect")
                        .foregroundStyle(.white)
                }
                    .compatibilityButtonStyle(.prominent)
                    .compatibilityRoundedButtonBorderShape(radius: 10)
                    .frame(maxWidth: .infinity)

            }
        }
    }

    @ViewBuilder
    private var connectionRemotePhoto: some View {
        if settings.selectedRemoteProfile?.model.isAppleSiriRemote == true {
            UnrecognizedRemotePhoto()
                .frame(width: 82, height: 166)
        } else if settings.selectedRemoteProfile?.model.isChromecastRemote == true {
            UnrecognizedRemotePhoto()
                .frame(width: 82, height: 166)
        } else if let model = settings.selectedRemoteProfile?.model,
                  let resource = VoiceRemoteCatalog.photoResource(for: model) {
            // 型号在目录里 → 用目录指定的那张真机图。
            RemoteCatalogPhoto(resourceName: resource)
                .frame(width: 82, height: 166)
        } else {
            // 型号目录里没有这个型号（.unknown、或还没选设备）：**不套用任何一款真机图**。
            // App 里每张图都对应一个验证过的型号，给未识别设备画上 RC003 等于界面声称
            // 支持一台从未验证过的遥控器。
            UnrecognizedRemotePhoto()
                .frame(width: 82, height: 166)
        }
    }

    private func connectionStatusLine(symbol: String, text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var audioSettingsPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 13) {
                Text("audio.voice_output.section_title")
                    .font(.headline)

                HStack(spacing: 14) {
                    Text("audio.output.title")
                        .frame(width: 92, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { settings.selectedAudioDeviceUID },
                        set: { value in
                            settings.selectedAudioDeviceUID = value
                            model.applyAudioSettings()
                        }
                    )) {
                        Text("audio.output.disabled").tag("")
                        ForEach(model.audioDevices, id: \.uid) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 270)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 14) {
                        Text("audio.gain.title")
                            .frame(width: 92, alignment: .leading)
                        Slider(value: Binding(
                            get: { settings.gainDB },
                            set: { settings.gainDB = $0 }
                        ), in: 0...24, step: 1)
                        Text("\(Int(settings.gainDB)) dB")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 54, alignment: .trailing)
                    }

                    Text("audio.gain.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 106)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("audio.status.title")
                        .frame(width: 92, alignment: .leading)
                    Spacer(minLength: 10)
                    Text(model.audioStatus.text(using: localization))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 10) {
                    Button {
                        model.refreshAudioDevices()
                    } label: {
                        Text("audio.action.refresh_devices")
                    }
                        .compatibilityButtonStyle(.standard)
                }

                Text("audio.output.privacy_help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var audioCompatibilityPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("audio.compatibility.section_title")
                            .font(.headline)
                        Text("audio.compatibility.microphone_label")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Text(model.doubaoAudioStatus.text(using: localization))
                        .font(.caption)
                        .foregroundStyle(model.hasDoubaoAudioDevice ? .green : .orange)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 10) {
                    Button(LocalizedMessage(
                        "audio.compatibility.select_microphone", arguments: [
                            DoubaoAudioDevicePolicy.device(in: model.audioDevices)?.name ?? DoubaoAudioDevicePolicy.deviceName
                        ]
                    ).text(using: localization)) { model.selectDoubaoAudioDevice() }
                        .compatibilityButtonStyle(.prominent)
                        .disabled(!model.hasDoubaoAudioDevice)
                    Button("audio.compatibility.open_install_guide") {
                        model.openDoubaoDriverInstructions(using: localization)
                    }
                    .compatibilityButtonStyle(.standard)
                }

                Text("audio.compatibility.help_plain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
