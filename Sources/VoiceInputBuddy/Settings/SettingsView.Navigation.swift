import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteCore
import BuddyRemoteUI
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var webRemoteSessionView: some View {
        WebRemoteSessionView(
            model: model,
            localization: WebRemoteSessionLocalization(
                locale: localization.locale,
                text: localization.text
            ),
            membershipRequiredView: membershipFeature.membershipRequiredView(remoteAuthorizationDenied: true) {
                isWebRemoteSessionPresented = false
                selectedSection = .membership
                membershipFeature.refreshIfNeeded()
            },
            onDiagnostic: { AppLogger.shared.write($0) }
        )
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            WindowDragArea()
                .frame(height: SettingsPageBehavior.sidebarTopDragHeight)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(verbatim: localization.text("app.name"))
                    .multilineTextAlignment(.center)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(visibleSections) { section in
                        sidebarButton(section)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var visibleSections: [SettingsSection] {
        SettingsPageBehavior.sidebarSections(
            privateFeatureVisible: privateFeature.isFeatureVisible,
            macroFeatureVisible: macroFeature.isFeatureVisible,
            buttonProfilesVisible: macroFeature.isButtonProfilesVisible,
            membershipVisible: membershipFeature.isFeatureVisible
        )
    }

    private func sidebarButton(_ section: SettingsSection) -> some View {
        let isSelected = (selectedSection == .commonPhrases ? .mapping : selectedSection) == section
        return Button {
            selectSidebarSection(section)
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: sectionSystemImage(section))
                        .font(.system(size: 21, weight: .semibold))
                    if SettingsPageBehavior.showsUpdateBadge(
                        for: section,
                        hasUnseenUpdate: updateInformation.hasUnseenUpdate
                    ) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 4, y: -3)
                            .accessibilityHidden(true)
                    }
                }
                if section == .privateFeature
                    || section == .macros
                    || section == .buttonProfiles
                    || section == .membership {
                    Text(sectionTitle(section))
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .compatibilityFocusEffectDisabled()
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(
            SettingsPageBehavior.showsUpdateBadge(
                for: section,
                hasUnseenUpdate: updateInformation.hasUnseenUpdate
            ) ? Text("settings.update_badge.accessibility_value") : Text("")
        )
    }

    private func selectSidebarSection(_ section: SettingsSection) {
        selectedSection = section
        if SettingsPageBehavior.marksUpdateAsSeen(whenSelecting: section) {
            updateInformation.markAvailableUpdateSeen()
        }
    }

    @ViewBuilder
    var selectedPage: some View {
        switch SettingsPageBehavior.visibleSection(for: selectedSection) {
        case .connection:
            connectionPage
        case .integration:
            integrationPage
        case .privateFeature:
            if privateFeature.isFeatureVisible {
                privateFeature.settingsView()
            } else {
                aboutPage
            }
        case .macros:
            if macroFeature.isFeatureVisible {
                VStack(spacing: 0) {
                    macroFeature.settingsView(
                        selectedRemoteProfileID: settings.selectedRemoteProfileID,
                        remoteModel: settings.selectedRemoteProfile?.model,
                        configuredActionTitle: { buttonValue, triggerValue in
                            guard let button = RemoteButton(rawValue: buttonValue),
                                  let trigger = ButtonTrigger(rawValue: triggerValue)
                            else { return nil }
                            return mappingActionSummary(for: button, trigger: trigger)
                        },
                        settings: settings,
                        onEditBinding: { device, profile, button, trigger in
                            preservesMappingContextOnNavigation = true
                            if let device { settings.selectRemoteProfile(device) }
                            editingMappingProfileID = profile
                            mappingEditingTarget = ShortcutEditingTarget(button: button, trigger: trigger)
                            selectedSection = .mapping
                        },
                        onBindToButton: {
                            preservesMappingContextOnNavigation = true
                            mappingEditingTarget = nil
                            mappingActionFilter = .custom
                            mappingMacroSearch = ""
                            selectedSection = .mapping
                        }
                    )
                }
            } else {
                aboutPage
            }
        case .buttonProfiles:
            if macroFeature.isButtonProfilesVisible {
                VStack(spacing: 0) {
                    macroFeature.buttonProfilesView(
                        selectedRemoteProfileID: settings.selectedRemoteProfileID,
                        remoteModel: settings.selectedRemoteProfile?.model,
                        hostActionSections: buttonProfileHostActionSections,
                        onEditKeys: { profile in
                            preservesMappingContextOnNavigation = true
                            editingMappingProfileID = profile
                            selectedSection = .mapping
                        },
                        chromecastReservedControlIDs: buttonProfilesChromecastReservedControls,
                        membershipNotice: membershipFeature.membershipRequiredView(forButtonProfiles: true) {
                            selectedSection = .membership
                            membershipFeature.refreshIfNeeded()
                        }
                    )
                }
            } else {
                aboutPage
            }
        case .membership:
            if membershipFeature.isFeatureVisible {
                membershipFeature.settingsView()
            } else {
                aboutPage
            }
        case .mapping:
            if let device = settings.selectedRemoteProfile,
               device.model.isAppleSiriRemote || device.model.isChromecastRemote {
                settingsPage {
                    PageHeader(title: localization.text("button_mapping.page.title"))
                } content: {
                    Text(localization.text("button_mapping.unsupported_device"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                mappingPage
            }
        case .commonPhrases:
            CommonPhraseSettingsView(store: model.commonPhraseStore) {
                selectedSection = .mapping
            }
        case .permissions:
            permissionsPage
        case .about:
            aboutPage
        }
    }

    func settingsPage<Header: View, Content: View>(
        contentPadding: CGFloat = 22,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            header()
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .padding(contentPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .compatibilityScrollEdgeEffect()
        }
    }
}
