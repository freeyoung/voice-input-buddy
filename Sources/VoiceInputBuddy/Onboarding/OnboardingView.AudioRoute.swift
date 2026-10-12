import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteUI
import BuddyRemoteCore
import SwiftUI

extension OnboardingView {
    var audioContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle("onboarding.audio.title")
            Text(verbatim: localization.text("onboarding.audio.detail"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusCard(
                icon: "mic.fill",
                title: localization.text("settings.driver.title"),
                detail: localization.text(microphoneDriverInstalled
                    ? "settings.driver.installed" : "settings.driver.missing"),
                isComplete: microphoneDriverInstalled
            )
            HStack {
                Button(localization.text("audio.action.refresh_devices")) {
                    model.refreshAudioDevices()
                }
                Button(localization.text("audio.compatibility.open_install_guide")) {
                    model.openDoubaoDriverInstructions(using: localization)
                }
            }
            .buttonStyle(.bordered)
            Text(verbatim: localization.text("settings.driver.reload_help"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if supportedAudioDevices.isEmpty {
                statusCard(
                    icon: "waveform.badge.magnifyingglass",
                    title: localization.text("onboarding.audio.no_devices"),
                    detail: localization.text("onboarding.audio.device_detail"),
                    isComplete: false
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(supportedAudioDevices, id: \.uid) { device in
                        audioDeviceRow(device)
                    }
                }
            }

            statusCard(
                icon: onboardingAudioReady
                    ? "checkmark.circle.fill"
                    : "speaker.wave.2",
                title: selectedAudioDeviceTitle,
                detail: selectedAudioDeviceDetail,
                isComplete: onboardingAudioReady
            )

            if failureReason == .audioNoOutputDevice ||
                failureReason == .audioSelectedDeviceMissing {
                onboardingActionButton(id: "audio.install-guide") {
                    if interactionProbe == nil {
                        model.openDoubaoDriverInstructions(using: localization)
                    }
                } label: {
                    Text(verbatim: localization.text("audio.compatibility.open_install_guide"))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func audioDeviceRow(_ device: AudioDeviceInfo) -> some View {
        let isSelected = settings.selectedAudioDeviceUID == device.uid
        return onboardingActionButton(id: "audio.device.\(device.uid)") {
            settings.selectedAudioDeviceUID = device.uid
            model.applyAudioSettings(reason: "onboarding_audio_device_selected")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
