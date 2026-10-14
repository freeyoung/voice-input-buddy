import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteUI
import BuddyRemoteCore
import SwiftUI

extension OnboardingView {
    var remoteAvailabilityContent: some View {
        let compact = availablePhysicalControlSources.count > 1
        let physicalColumns = [GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            onboardingTitle("onboarding.control_source.title")
            Text(verbatim: localization.text("onboarding.control_source.detail"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: localization.text("onboarding.control_source.hardware"))
                .font(.system(size: 13, weight: .semibold))

            LazyVGrid(
                columns: physicalColumns,
                spacing: compact ? 8 : 10
            ) {
                ForEach(availablePhysicalControlSources) { source in
                    if source == .siriRemote {
                        ForEach(OnboardingAppleRemoteGeneration.allCases) { generation in
                            controlSourceCard(
                                source,
                                emphasized: true,
                                appleGeneration: generation
                            )
                        }
                    } else {
                        controlSourceCard(source, emphasized: true)
                    }
                }
            }

            VStack(spacing: 8) {
                ForEach(PlannedRemoteDevice.allCases.filter { !$0.isAvailable }) { device in
                    unsupportedControlSourceCard(
                        titleKey: device.titleKey,
                        icon: device.icon
                    )
                }
            }

        }
    }

    private func unsupportedControlSourceCard(titleKey: String, icon: String) -> some View {
        Button {} label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.text(titleKey))
                        .font(.system(size: 13, weight: .semibold))
                    Text(localization.text("remote.catalog.planned"))
                        .font(.system(size: 12))
                }
                Spacer(minLength: 4)
                Image(systemName: "circle")
            }
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityIdentifier(titleKey)
    }

    private var availablePhysicalControlSources: [OnboardingControlSource] {
        OnboardingBuildCapabilities.availableControlSources.filter {
            [.xiaomiRemote, .siriRemote].contains($0)
        }
    }

    private func controlSourceCard(
        _ source: OnboardingControlSource,
        emphasized: Bool,
        appleGeneration: OnboardingAppleRemoteGeneration? = nil
    ) -> some View {
        let compact = availablePhysicalControlSources.count > 1
        let actionID = appleGeneration.map {
            "control-source.\(source.rawValue).\($0.rawValue)"
        } ?? "control-source.\(source.rawValue)"
        let isSelected = settings.onboardingControlSource == source &&
            (source != .siriRemote || settings.onboardingAppleRemoteGeneration == appleGeneration)
        return onboardingActionButton(id: actionID) {
            if let appleGeneration {
                selectAppleRemote(appleGeneration)
            } else {
                selectControlSource(source)
            }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                controlSourceThumbnail(source, emphasized: emphasized)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.text(appleGeneration?.titleKey ?? (source == .xiaomiRemote ? PlannedRemoteDevice.xiaomi.titleKey : source.titleKey)))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    if source == .xiaomiRemote {
                        Text(verbatim: localization.text("onboarding.control_source.recommended"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(localization.text(source.detailKey))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(compact ? 2 : 3)
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected
                    ? "largecircle.fill.circle"
                    : "circle")
                    .foregroundStyle(isSelected
                        ? Color.accentColor
                        : Color.secondary)
            }
            .padding(compact ? 10 : 12)
            .frame(
                maxWidth: .infinity,
                minHeight: emphasized
                    ? (availablePhysicalControlSources.count > 1 ? 116 : 104)
                    : 72,
                alignment: .topLeading
            )
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.09)
                    : Color.primary.opacity(emphasized ? 0.04 : 0.025),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.65)
                            : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func controlSourceThumbnail(
        _ source: OnboardingControlSource,
        emphasized: Bool
    ) -> some View {
        switch source {
        case .xiaomiRemote:
            if let image = bundledRemoteImage(resourceName: "BuddyRemoteIllustration") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: emphasized ? 42 : 30, height: emphasized ? 72 : 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: controlSourceIcon(source))
                    .font(.system(size: emphasized ? 21 : 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: emphasized ? 40 : 34, height: emphasized ? 40 : 34)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
        case .siriRemote:
            Image(systemName: controlSourceIcon(source))
                .font(.system(size: emphasized ? 21 : 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: emphasized ? 40 : 34, height: emphasized ? 40 : 34)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        default:
            Image(systemName: controlSourceIcon(source))
                .font(.system(size: emphasized ? 21 : 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: emphasized ? 40 : 34, height: emphasized ? 40 : 34)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    var gestureModeChoice: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: localization.text("onboarding.gesture.title"))
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                ForEach(VoiceGestureMode.allCases) { mode in
                    onboardingActionButton(id: "gesture.\(mode.rawValue)") {
                        selectPreferredGesture(mode)
                    } label: {
                        Label(
                            localization.text("onboarding.gesture.\(mode.rawValue)"),
                            systemImage: effectivePreferredGesture == mode
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func pairingPlanSummary(_ plan: OnboardingVoicePairingPlan) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label {
                Text(verbatim: localization.text("onboarding.pairing_plan.title"))
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
                .font(.system(size: 13, weight: .semibold))
            Text(OnboardingVoiceGesturePrompt.text(
                for: plan.binding.gestureMode,
                locale: localization.locale
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if plan.binding.tool == .vokie {
                HStack(spacing: 8) {
                    onboardingActionButton(id: "vokie.open") {
                        guard let url = VokieDeepLink.launchURL(for: plan) else { return }
                        openOnboardingURL(url)
                    } label: {
                        Text(verbatim: localization.text("onboarding.vokie.open"))
                    }
                    .buttonStyle(.bordered)
                    if let vokieDeepLinkStatus {
                        Text(localization.text("onboarding.vokie.status.\(vokieDeepLinkStatus.rawValue)"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(vokieDeepLinkStatus == .failed ? Color.red : Color.secondary)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
