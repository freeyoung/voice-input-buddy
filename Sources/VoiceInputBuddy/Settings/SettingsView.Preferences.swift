import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteCore
import BuddyRemoteUI
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var aboutPage: some View {
        settingsPage(contentPadding: 28) {
            PageHeader(title: localization.text("settings.page.title"))
        } content: {
            GlassPanel {
                HStack(spacing: 18) {
                    Image(systemName: "wand.and.stars").font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("about.preferences.restart_onboarding").font(.headline)
                        Text("about.preferences.restart_onboarding_help")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("about.preferences.restart_onboarding_action") {
                        settings.restartOnboarding()
                    }
                    .compatibilityButtonStyle(.prominent)
                    .controlSize(.large)
                }
            }
            .padding(.bottom, 16)
            CompatibilityGlassContainer(spacing: 0) {
                VStack(spacing: 0) {
                    Group {
                        HStack(alignment: .top, spacing: 28) {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(nsImage: appIconCatalog.image(
                                    for: settings.appIconIdentifier
                                ))
                                    .resizable()
                                    .frame(width: 72, height: 72)
                                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                                Text("app.name")
                                    .font(.title3.weight(.semibold))
                                Text("settings.application.tagline")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(minWidth: 190, maxWidth: 230, alignment: .leading)

                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text("about.version.current")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    Button(action: revealPrivateEnrollmentIfNeeded) {
                                        Text(currentVersion)
                                            .font(.system(size: 13, weight: .medium))
                                            .monospacedDigit()
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    if case .available = updateInformation.state {
                                        StatusPill(
                                            text: localization.text("about.version.available"),
                                            tint: .green
                                        )
                                    }
                                    Spacer(minLength: 8)
                                }

                                if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
                                    HStack(spacing: 12) {
                                        Button(action: checkForUpdates) {
                                            Label(
                                                "menu.check_for_updates",
                                                systemImage: "arrow.triangle.2.circlepath"
                                            )
                                        }
                                        .compatibilityButtonStyle(.standard)
                                        .fixedSize(horizontal: true, vertical: false)

                                        Spacer(minLength: 12)

                                        Toggle(
                                            "about.version.check_prerelease",
                                            isOn: $settings.checksForPreReleaseUpdates
                                        )
                                        .toggleStyle(.switch)
                                        .font(.system(size: 12))
                                    }

                                    Divider()

                                    updateInformationContent
                                    if case let .available(update) = updateInformation.state {
                                        HStack {
                                            Spacer()
                                            Button(action: checkForUpdates) {
                                                Text(String(
                                                    format: localization.text("about.version.update_to"),
                                                    locale: localization.locale,
                                                    arguments: [update.displayVersion]
                                                ))
                                            }
                                            .compatibilityButtonStyle(.prominent)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                        .overlay(alignment: .bottom) { Divider() }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.general.title")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if membershipFeature.isEnvironmentSettingsVisible {
                            membershipFeature.serviceEnvironmentSettingsView()
                                .padding(.vertical, 8)
                        }

                        Group {
                            VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("about.configuration.title")
                                        .font(.subheadline.weight(.semibold))
                                    Text("about.configuration.export_description")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 16)
                                Button("about.configuration.export", action: exportConfiguration)
                                    .compatibilityButtonStyle(.standard)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: 150)
                                Button("about.configuration.import", action: importConfiguration)
                                    .compatibilityButtonStyle(.standard)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: 150)
                            }
                            .padding(.vertical, 8)
                            if macroFeature.isFeatureVisible {
                                Text(localization.text("settings.portable_configuration.title"))
                                    .font(.system(size: 12, weight: .medium))
                                macroFeature.portableTransferView(profileID: settings.selectedRemoteProfileID,
                                    model: settings.selectedRemoteProfile?.model)
                            }

                            if let configurationStatus {
                                Divider()
                                Label(
                                    configurationStatus.message.text(using: localization),
                                    systemImage: configurationStatus.systemImage
                                )
                                .font(.caption)
                                .foregroundStyle(configurationStatus.tint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }

                            Divider()

                            HStack(spacing: 14) {
                                Image(systemName: "dock.rectangle")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("about.preferences.show_dock_icon")
                                        .font(.subheadline.weight(.semibold))
                                    Text("about.preferences.show_dock_icon_help")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { settings.showDockIcon },
                                    set: { setDockIconVisible($0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.vertical, 8)

                            Divider()

                            if appIconCatalog.options.count > 1 {
                                appIconPreferenceRow
                                Divider()
                            }

                            HStack(spacing: 14) {
                                Image(systemName: "menubar.rectangle")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("about.preferences.show_status_bar_icon")
                                        .font(.subheadline.weight(.semibold))
                                    Text("about.preferences.show_status_bar_icon_help")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { settings.showStatusBarIcon },
                                    set: { setStatusBarIconVisible($0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.vertical, 8)

                            Divider()

                            HStack(spacing: 14) {
                                Image(systemName: "power")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("settings.general.launch_behavior")
                                        .font(.subheadline.weight(.semibold))
                                    Text("settings.general.launch_behavior_help")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 12)
                                HStack(spacing: 10) {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("about.preferences.launch_at_login")
                                            .font(.system(size: 12, weight: .medium))
                                        Toggle("", isOn: Binding(
                                            get: { loginItemService.isEnabled },
                                            set: { loginItemService.setEnabled($0) }
                                        ))
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                    }

                                    Divider()
                                        .frame(height: 34)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("about.preferences.open_main_window_at_launch")
                                            .font(.system(size: 12, weight: .medium))
                                        Toggle("", isOn: $settings.openMainWindowAtLaunch)
                                            .labelsHidden()
                                            .toggleStyle(.switch)
                                    }
                                }
                            }
                            .padding(.vertical, 8)

                            if loginItemService.requiresApproval {
                                Text("about.preferences.launch_at_login_requires_approval")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.bottom, 8)
                                Button(
                                    "about.preferences.launch_at_login_open_system_settings",
                                    action: loginItemService.openLoginItemsSettings
                                )
                                .compatibilityButtonStyle(.standard)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            } else if loginItemService.didFailToUpdate {
                                Text("about.preferences.launch_at_login_update_failed")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.bottom, 8)
                            }

                            Divider()

                            HStack(spacing: 14) {
                                Image(systemName: "globe")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("about.preferences.language")
                                        .font(.subheadline.weight(.semibold))
                                    Text("about.preferences.language_description")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 20)
                                Picker("about.preferences.language", selection: Binding(
                                    get: { localization.language },
                                    set: { localization.select($0) }
                                )) {
                                    ForEach(AppLanguage.allCases) { language in
                                        Text(languageTitle(language)).tag(language)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 300)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Divider() }

                    if privateFeature.shouldShowEnrollment {
                        privateFeature.enrollmentView()
                    }

                    if macroFeature.shouldShowEnrollment {
                        macroFeature.enrollmentView()
                    }

                    inlineDiagnosticsSection

                    if model.isRC003VoiceExtensionTestEnabled {
                        Text("测试长时间语音功能")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }

                    settingsSupportSection
                }
            }
        }
        .onAppear {
            guard !SettingsVisualRenderingPolicy.isScreenshotHarness else { return }
            guard UpdateCheckPolicy(
                checksForPreReleaseUpdates: settings.checksForPreReleaseUpdates
            ).refreshesAboutInformationOnAppear else { return }
            refreshUpdateInformation()
        }
    }

    private var settingsSupportSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("about.support.feedback")
                    .font(.subheadline.weight(.semibold))
                Text("about.support.feedback_description")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Link(destination: localization.localizedWebsiteURL) {
                Label("about.support.website", systemImage: "globe")
            }
            .compatibilityButtonStyle(.standard)
            Link(destination: AppLinks.githubRepository) {
                Label("about.support.github", systemImage: "link")
            }
            .compatibilityButtonStyle(.standard)
            Link(destination: AppLinks.feedback) {
                Label("about.support.feedback_action", systemImage: "arrow.up.right")
            }
            .compatibilityButtonStyle(.standard)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Divider() }
    }
}
