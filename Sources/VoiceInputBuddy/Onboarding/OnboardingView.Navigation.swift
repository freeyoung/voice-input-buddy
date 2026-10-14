import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteUI
import BuddyRemoteCore
import SwiftUI

extension OnboardingView {
    var phaseHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(settings.onboardingPurpose.steps.enumerated()), id: \.element.rawValue) { index, step in
                    let current = step == settings.onboardingStep
                    let completed = settings.onboardingPurpose.progress(at: step) < settings.onboardingPurpose.progress(at: settings.onboardingStep)
                    VStack(spacing: 7) {
                        Text(completed ? "✓" : "\(index + 1)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(current ? Color.white : Color.secondary)
                            .frame(width: 25, height: 25)
                            .background(current ? Color.accentColor : Color.primary.opacity(0.07), in: Circle())
                        Text(localization.text("onboarding.step.\(step.rawValue)"))
                            .font(.system(size: 11, weight: current ? .semibold : .regular))
                            .foregroundStyle(current ? Color.primary : Color.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 22)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.09))
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: proxy.size.width * settings.onboardingPurpose.progress(at: settings.onboardingStep))
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 28)
        }
        .padding(.top, 12)
        .frame(height: 105)
    }

    var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let previous = previousStep {
                onboardingActionButton(id: "back") {
                    goBack(to: previous)
                } label: {
                    Label {
                        Text(verbatim: localization.text("onboarding.action.back"))
                    } icon: {
                        Image(systemName: "arrow.left")
                    }
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .modifier(OnboardingFocusEffectDisabledModifier())
                .accessibilityIdentifier("onboarding.back")
                .padding(.bottom, 24)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    stepContent
                    if let failureReason, shouldShowStandaloneRecoveryCard(failureReason) {
                        recoveryCard(for: failureReason)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollIndicators(.visible)

            HStack(alignment: .center, spacing: 16) {
                if settings.onboardingStep == .permissions {
                    Picker(selection: Binding(
                        get: { localization.language },
                        set: { localization.select($0) }
                    )) {
                        Text(localization.text("language.system")).tag(AppLanguage.system)
                        Text("简体中文").tag(AppLanguage.simplifiedChinese)
                        Text("English").tag(AppLanguage.english)
                    } label: {
                        Image(systemName: "globe")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 190)
                    .accessibilityLabel(localization.text("about.preferences.language"))
                    .accessibilityIdentifier("onboarding.language")
                }
                if settings.onboardingStep == .voiceTool && !canContinue {
                    Text(verbatim: localization.text("onboarding.voice_tool.guide.continue_hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                }
                Spacer(minLength: 0)
                if settings.canDismissOnboarding {
                    onboardingActionButton(id: "dismiss") {
                        settings.dismissOnboarding()
                        if let profileID = settings.selectedRemoteProfileID {
                            model.selectRemoteProfile(profileID)
                        }
                        model.applyHIDSettings()
                    } label: {
                        Text(localization.text("onboarding.action.dismiss"))
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isStreaming)
                    .accessibilityIdentifier("onboarding.dismiss")
                }
                if settings.onboardingStep != .audio {
                    onboardingActionButton(id: "continue", action: continueFlow) {
                        Text(localization.text(primaryActionKey))
                            .font(.system(size: 14, weight: .semibold))
                            .frame(minWidth: 118)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canContinue)
                    .accessibilityIdentifier("onboarding.continue")
                }
            }
            .padding(.top, 14)
        }
        .padding(.top, settings.onboardingStep == .permissions ? 12 : 28)
        .padding(.horizontal, 48)
        .padding(.bottom, 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch settings.onboardingStep {
        case .voiceTool:
            voiceToolContent
        case .remoteAvailability:
            remoteAvailabilityContent
        case .permissions:
            permissionsContent
        case .remote:
            remoteContent
        case .audio:
            audioContent
        case .voiceTest:
            voiceTestContent
        case .controls:
            controlsContent
        case .complete:
            completeContent
        }
    }

    func continueFlow() {
        guard canContinue else { return }
        if settings.onboardingStep == .remoteAvailability,
           let device = settings.onboardingDevice,
           !device.canStartSetup {
            showUnsupportedDeviceNotice = true
            return
        }
        if settings.onboardingStep == .voiceTool {
            stageCurrentDocumentedPairingPlanIfPossible()
        }
        if settings.onboardingStep == .voiceTest {
            settings.verifyOnboardingVoiceBinding()
        }
        if settings.onboardingStep != .voiceTest {
            settings.recordFirstUseEvent(.passed, step: settings.onboardingStep)
        }
        if settings.onboardingStep == .remoteAvailability,
           settings.onboardingControlMethod == .physicalRemote {
            settings.customMappingEnabled = true
        }
        if settings.onboardingStep == .permissions {
            if settings.onboardingControlMethod == .physicalRemote {
                settings.customMappingEnabled = true
            }
        }
        if settings.onboardingStep == .complete {
            settings.completeOnboarding()
            return
        }
        if let next = settings.onboardingPurpose.nextStep(after: settings.onboardingStep) {
            settings.setOnboardingStep(next)
        }
    }

    private var previousStep: OnboardingStep? {
        return settings.onboardingPurpose.previousStep(before: settings.onboardingStep)
    }

    private func goBack(to previous: OnboardingStep) {
        AppLogger.shared.write(
            "ONBOARDING NAVIGATION from=\(settings.onboardingStep.rawValue) " +
                "to=\(previous.rawValue) reason=user_back"
        )
        if settings.stagedVoiceToolBinding != nil {
            settings.discardOnboardingVoiceTrial()
            model.applyHIDSettings()
        }
        settings.setOnboardingStep(previous)
    }

    private struct OnboardingFocusEffectDisabledModifier: ViewModifier {
        @ViewBuilder
        func body(content: Content) -> some View {
            if #available(macOS 14.0, *) {
                content.focusEffectDisabled()
            } else {
                content
            }
        }
    }
}
