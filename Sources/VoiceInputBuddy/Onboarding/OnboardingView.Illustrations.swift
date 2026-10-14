import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteUI
import BuddyRemoteCore
import SwiftUI

extension OnboardingView {
    var rightPane: some View {
        ZStack {
            LinearGradient(
                colors: rightPaneGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(rightPaneHighlightColor)
                .frame(width: 360, height: 360)
                .blur(radius: 10)
                .offset(x: 110, y: -110)

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if settings.onboardingStep == .voiceTool,
                       settings.onboardingVoiceTool != .unselected {
                        inputMethodGuide(for: settings.onboardingVoiceTool)
                            .frame(maxWidth: 440)
                            .padding(.horizontal, 28)
                    } else if settings.onboardingStep == .voiceTool {
                        welcomeIllustration
                    } else if settings.onboardingStep == .remoteAvailability {
                        selectedDeviceIllustration
                    } else if settings.onboardingStep == .complete {
                        completeIllustration
                    } else {
                        selectedControlIllustration
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(minHeight: 0)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeIllustration: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 118, height: 118)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            Image(systemName: "waveform")
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(Color.accentColor)
                Text(verbatim: localization.text("onboarding.illustration.tagline"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var selectedDeviceIllustration: some View {
        VStack(spacing: 16) {
            if let device = settings.onboardingDevice,
               let image = bundledRemoteImage(resourceName: device.illustrationResource) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 190, maxHeight: 480)
                    .accessibilityLabel(localization.text("remote.catalog.illustration"))
                if showUnsupportedDeviceNotice && !device.canStartSetup {
                    Text(localization.text("remote.catalog.unsupported_notice"))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("remote.unsupported-notice")
                }
            } else {
                remoteAvailabilityIllustration
            }
        }
        .padding(28)
    }

    private var remoteIllustration: some View {
        VStack(spacing: 16) {
            onboardingRemotePhoto
            sideStatusPanel
        }
        .padding(28)
    }

    @ViewBuilder
    private var onboardingRemotePhoto: some View {
        switch OnboardingRemotePhotoKind.resolve(
            source: settings.onboardingControlSource,
            selectedModel: settings.selectedRemoteProfile?.model
        ) {
        case let .bundled(resourceName):
            if let image = bundledRemoteImage(resourceName: resourceName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 190, maxHeight: 480)
                    .shadow(color: .black.opacity(0.20), radius: 16, y: 10)
            } else {
                remotePhotoPlaceholder
            }
        case .siriRemote:
            remotePhotoPlaceholder
        case .chromecastRemote:
            remotePhotoPlaceholder
        case .placeholder:
            remotePhotoPlaceholder
        }
    }

    private var remotePhotoPlaceholder: some View {
        Image(systemName: "appletvremote.gen4.fill")
            .font(.system(size: 180))
            .foregroundStyle(.secondary)
    }

    private var controlMethodIllustration: some View {
        VStack(spacing: 26) {
            HStack(spacing: 38) {
                Image(systemName: "iphone")
                Image(systemName: "safari.fill")
            }
            .font(.system(size: 58, weight: .medium))
            .foregroundStyle(Color.accentColor)
                Text(verbatim: localization.text("onboarding.control_method.illustration"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var remoteAvailabilityIllustration: some View {
        VStack(spacing: 24) {
            Image(systemName: "appletvremote.gen4.fill")
                .font(.system(size: 150, weight: .medium))
                .foregroundStyle(Color.accentColor)
                Text(verbatim: localization.text("onboarding.remote_availability.illustration"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedControlIllustration: some View {
        switch settings.onboardingControlMethod {
        case .physicalRemote, .unselected:
            remoteIllustration
        case .iPhoneApp:
            iPhoneRemoteIllustration
        case .webRemote:
            webRemoteIllustration
        }
    }

    private var iPhoneRemoteIllustration: some View {
        VStack(spacing: 18) {
            if !model.isPhoneRemoteConnected,
               let invitation = model.phoneRemoteInvitation,
               let qrCode = PhoneRemoteInvitationQRCode.image(for: invitation) {
                Image(nsImage: qrCode)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
        .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                Text(verbatim: localization.text("onboarding.iphone_remote.scan"))
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: model.isPhoneRemoteConnected
                    ? "iphone.gen3.radiowaves.left.and.right"
                    : "iphone.gen3")
                    .font(.system(size: 150, weight: .light))
                    .foregroundStyle(
                        model.isPhoneRemoteConnected ? Color.green : Color.accentColor
                    )
            }
            sideStatusPanel
        }
        .padding(28)
    }

    @ViewBuilder
    private var webRemoteIllustration: some View {
        VStack(spacing: 16) {
            switch model.webRemoteState {
            case .waitingForPhone, .awaitingApproval:
                WebRemoteMiniProgramCodeView(
                    model: model,
                    localization: WebRemoteSessionLocalization(
                        locale: localization.locale,
                        text: localization.text
                    ),
                    size: 250,
                    onDiagnostic: { AppLogger.shared.write($0) }
                )
            case let .connected(deviceName):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Color.green)
                Text(deviceName)
                    .font(.system(size: 16, weight: .semibold))
            case .connecting:
                ProgressView()
                    .controlSize(.large)
                Text(verbatim: localization.text("onboarding.web_remote.connecting"))
                    .font(.system(size: 15, weight: .semibold))
            case .unavailable, .failed:
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 82))
                    .foregroundStyle(Color.orange)
                Text(verbatim: localization.text("onboarding.web_remote.unavailable"))
                    .font(.system(size: 15, weight: .semibold))
            case .disabled:
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 100))
                    .foregroundStyle(Color.accentColor)
                Text(verbatim: localization.text("onboarding.web_remote.preparing"))
                    .font(.system(size: 15, weight: .semibold))
            }
            sideStatusPanel
        }
        .padding(28)
    }

    private var completeIllustration: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.14))
                    .frame(width: 170, height: 170)
                Image(systemName: "checkmark")
                    .font(.system(size: 74, weight: .bold))
                    .foregroundStyle(Color.green)
            }
                Text(verbatim: localization.text("onboarding.complete.illustration"))
                .font(.system(size: 18, weight: .semibold))
        }
    }
}
