import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteCore
import BuddyRemoteUI
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var buttonProfilesChromecastReservedControls: Set<String> {
        ["left", "right", "select"]
    }

    func mappingConfiguration(for button: RemoteButton, trigger: ButtonTrigger) -> ConfiguredButtonAction {
        if let profile = editingMappingProfileID {
            return macroFeature.profileBinding(device: settings.selectedRemoteProfileID, profile: profile,
                button: button, trigger: trigger)
                ?? settings.configuredBaseAction(for: button, trigger: trigger)
        }
        return settings.configuredBaseAction(for: button, trigger: trigger)
    }

    private func saveMappingBinding(_ configured: ConfiguredButtonAction, button: RemoteButton, trigger: ButtonTrigger) {
        let operationID = UUID().uuidString
        if configured.action == .combinationAction {
            AppLogger.shared.write("BUTTON CONFIGURATION operation_id=\(operationID) action=select_combination phase=started result=requested")
        }
        if let profile = editingMappingProfileID {
            macroFeature.setProfileBinding(configured, profile: profile, button: button, trigger: trigger,
                displayName: configured.action == .customShortcut
                    ? configured.shortcut?.visualDisplayName(using: localization) ?? configured.action.displayName(using: localization)
                    : configured.action.displayName(using: localization))
        } else {
            settings.setBaseBinding(configured, for: button, trigger: trigger, profileID: settings.selectedRemoteProfileID)
        }
        if configured.action == .combinationAction {
            let matches = mappingConfiguration(for: button, trigger: trigger) == configured
            AppLogger.shared.write("BUTTON CONFIGURATION operation_id=\(operationID) action=select_combination phase=completed result=\(matches ? "stored" : "not_stored") scope=\(editingMappingProfileID == nil ? "base" : "profile")")
        }
    }

    func setMappingAction(_ action: ButtonAction, for button: RemoteButton, trigger: ButtonTrigger) {
        var configured = mappingConfiguration(for: button, trigger: trigger)
        configured.action = action
        saveMappingBinding(configured, button: button, trigger: trigger)
    }

    func setMappingShortcut(_ shortcut: CustomKeyboardShortcut?, for button: RemoteButton, trigger: ButtonTrigger) {
        var configured = mappingConfiguration(for: button, trigger: trigger)
        configured.shortcut = shortcut
        saveMappingBinding(configured, button: button, trigger: trigger)
    }

    func setMappingApplicationProfileID(_ id: UUID?, for button: RemoteButton, trigger: ButtonTrigger) {
        var configured = mappingConfiguration(for: button, trigger: trigger)
        configured.applicationProfileID = id
        saveMappingBinding(configured, button: button, trigger: trigger)
    }

    private var mappingProfileSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localization.text("button_mapping.editing_profile")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let active = macroFeature.activeMappingProfileID(device: settings.selectedRemoteProfileID),
                   let profile = macroFeature.mappingProfiles(device: settings.selectedRemoteProfileID).first(where: { $0.id == active }) {
                    Text(localization.text("button_mapping.active_profile") + "：" + profile.name)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text(localization.text("button_mapping.active_profile") + "：" + localization.text("button_mapping.base_profile"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button(localization.text("button_mapping.base_profile")) { editingMappingProfileID = nil }
                        .tint(editingMappingProfileID == nil ? .accentColor : .secondary)
                    ForEach(macroFeature.mappingProfiles(device: settings.selectedRemoteProfileID)) { profile in
                        Button(profile.name) { editingMappingProfileID = profile.id; shortcutCaptureTarget = nil }
                            .tint(editingMappingProfileID == profile.id ? .accentColor : .secondary)
                    }
                }.buttonStyle(.bordered)
            }
        }
        .onAppear { macroFeature.prepareMappingDevice(settings.selectedRemoteProfileID) }
        .onChange(of: macroFeature.mappingProfiles(device: settings.selectedRemoteProfileID).map(\.id)) { _, ids in
            if let profile = editingMappingProfileID, !ids.contains(profile) {
                editingMappingProfileID = nil
                shortcutCaptureTarget = nil
            }
        }
        .onChange(of: settings.selectedRemoteProfileID) { _, _ in
            macroFeature.prepareMappingDevice(settings.selectedRemoteProfileID)
            if let profile = editingMappingProfileID,
               !macroFeature.mappingProfiles(device: settings.selectedRemoteProfileID).contains(where: { $0.id == profile }) {
                editingMappingProfileID = nil
            }
        }
    }

    @ViewBuilder
    func mappingInheritanceControl(button: RemoteButton, trigger: ButtonTrigger) -> some View {
            if let profile = editingMappingProfileID {
                Button(localization.text("button_mapping.inherit_base")) {
                    macroFeature.setProfileBinding(nil, profile: profile, button: button, trigger: trigger)
                }.buttonStyle(.bordered)
                if macroFeature.profileBinding(device: settings.selectedRemoteProfileID, profile: profile,
                    button: button, trigger: trigger) == nil {
                    Text(localization.text("button_mapping.inherited") + "：" + mappingActionSummary(for: button, trigger: trigger))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
    }

    func mappingMacroChoices(button: RemoteButton, trigger: ButtonTrigger,
                                     configured: ConfiguredButtonAction) -> some View {
        let searchQuery = mappingMacroSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingActions = macroFeature.libraryActions.filter {
            searchQuery.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(searchQuery) ||
                $0.id.localizedCaseInsensitiveContains(searchQuery)
        }
        let visibleActions = searchQuery.isEmpty ? Array(matchingActions.prefix(10)) : matchingActions
        return VStack(alignment: .leading, spacing: 10) {
            Text(localization.text("action.combination_action")).font(.system(size: 14, weight: .semibold))
            TextField(localization.text("button_mapping.search_macros"), text: $mappingMacroSearch)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(maxWidth: 280)
            VStack(spacing: 6) {
                ForEach(visibleActions) { action in
                    Button {
                        var binding = configured
                        binding.action = .combinationAction
                        binding.macroID = action.id
                        saveMappingBinding(binding, button: button, trigger: trigger)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up")
                            Text(action.name).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(String(format: localization.text("button_mapping.macro_step_count"), action.stepCount))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            if configured.action == .combinationAction && configured.macroID == action.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .background(configured.action == .combinationAction && configured.macroID == action.id
                            ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if configured.action == .combinationAction,
               !macroFeature.libraryActions.contains(where: { $0.id == configured.macroID }) {
                Text(localization.text("button_mapping.macro_unavailable")).font(.system(size: 13)).foregroundStyle(.orange)
            }
            Button(localization.text("button_mapping.manage_macros")) {
                mappingActionFilter = .custom
                mappingMacroSearch = ""
                selectedSection = .macros
            }
                .buttonStyle(.bordered)
        }
    }

    private var mappingPageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                PageHeader(title: localization.text("button_mapping.page.title"))
                mappingHeaderToggle
            }
            Text(localization.text("button_mapping.page.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var mappingPage: some View {
        hardwareMappingPage {
            RemoteMappingCanvas(
                selectedButton: $selectedRemoteButton,
                activeButtons: model.activeRemoteButtons,
                voiceActive: model.isStreaming,
                actionSummary: { button, trigger in mappingActionSummary(for: button, trigger: trigger) },
                onEdit: { button, trigger in
                    selectedRemoteButton = button
                    mappingActionFilter = .all
                    mappingEditingTarget = ShortcutEditingTarget(
                        button: button,
                        trigger: trigger
                    )
                },
                onVoiceSettings: { selectedSection = .integration }
            )
            .onReceive(model.$activeRemoteButtons) { buttons in
                selectedRemoteButton = MappingSelectionPolicy.selection(
                    current: selectedRemoteButton,
                    activeButtons: buttons,
                    isLocked: isMappingSelectionLocked
                )
            }
        }
    }

    private func hardwareMappingPage<HardwareCanvas: View>(
        includeSiriScrollArrow: Bool = false,
        @ViewBuilder hardwareCanvas: @escaping () -> HardwareCanvas
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                mappingPageHeader
                    .fixedSize(horizontal: true, vertical: false)
                mappingDevicePicker
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            ScrollViewReader { proxy in
                Group {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            Color.clear
                                .frame(height: 0)
                                .id("mapping-page-top")
                            if let profileID = editingMappingProfileID,
                               let profile = macroFeature.mappingProfiles(device: settings.selectedRemoteProfileID).first(where: { $0.id == profileID }) {
                                HStack {
                                    Text(localization.text("button_mapping.editing_profile") + "：" + profile.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Button(localization.text("button_mapping.base_profile")) { editingMappingProfileID = nil }
                                        .buttonStyle(.bordered)
                                }
                            }
                            configurationImportBanner
                            corruptedSettingsBanner

                            hardwareCanvas()

                            if let target = mappingEditingTarget {
                                mappingEditorPanel(target)
                                    .id("mapping-action-editor")
                            }


                            mappingFooter(includeSiriScrollArrow: includeSiriScrollArrow)
                            Color.clear.frame(height: 1).id("mapping-page-bottom")
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .id(settings.selectedRemoteProfileID)
                    .compatibilityScrollEdgeEffect()
                }
                .onChange(of: settings.selectedRemoteProfileID) { _, _ in
                    // 编辑器属于上一只遥控器；切换设备后不得把旧编辑区带到新页面。
                    mappingEditingTarget = nil
                    shortcutCaptureTarget = nil
                    applicationShortcutCaptureProfileID = nil
                    DispatchQueue.main.async {
                        proxy.scrollTo("mapping-page-top", anchor: .top)
                    }
                }
                .onAppear {
                    guard mappingEditingTarget != nil else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo("mapping-action-editor", anchor: .top)
                    }
                }
                .onChange(of: mappingEditingTarget?.id) { _, targetID in
                    guard targetID != nil else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("mapping-action-editor", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    /// Inline on purpose: an import that quietly dropped an entry must leave a trace the user
    /// can still read afterwards, and the repository's interface rules keep page-level notices
    /// flat inside the page rather than behind a sheet. Renders nothing when the last import
    /// adopted everything, so a clean import keeps the page's layout.
    @ViewBuilder
    private var configurationImportBanner: some View {
        if let notice = settings.configurationImportNotice {
            let rejected = ConfigurationImportNoticeText.rejectedSummary(
                for: notice.rejectedEntryStorageKeys,
                localize: localization.text
            )
            let missing = ConfigurationImportNoticeText.missingApplicationSummary(
                for: notice.applicationsMissingOnThisMac,
                localize: localization.text
            )
            GlassPanel {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localization.text(ConfigurationImportNoticeText.titleKey))
                            .font(.system(size: 12, weight: .semibold))
                        if let rejected {
                            Text(rejected)
                                .font(.system(size: 12))
                        }
                        if let missing {
                            Text(missing)
                                .font(.system(size: 12))
                        }
                        Text(localization.text(ConfigurationImportNoticeText.nextStepKey))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Inline on purpose: a sheet or alert here would be dismissed once and never seen again,
    /// and the repository's interface rules keep page-level notices flat inside the page.
    /// Renders nothing at all when no key failed to decode, so a healthy launch keeps its layout.
    @ViewBuilder
    private var corruptedSettingsBanner: some View {
        if let summary = CorruptedSettingsNotice.summary(
            for: settings.corruptedSettingKeys,
            localize: localization.text
        ) {
            GlassPanel {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localization.text(CorruptedSettingsNotice.titleKey))
                            .font(.system(size: 12, weight: .semibold))
                        Text(summary)
                            .font(.system(size: 12))
                        Text(localization.text(CorruptedSettingsNotice.recoveryKey))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(localization.text(CorruptedSettingsNotice.nextStepKey))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var mappingHeaderToggle: some View {
        Toggle("button_mapping.toggle.enabled", isOn: Binding(
            get: { settings.customMappingEnabled },
            set: setCustomMappingEnabled
        ))
        .font(.system(size: 14, weight: .medium))
        .toggleStyle(.switch)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func mappingEditorPanel(_ target: ShortcutEditingTarget) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(target.button.displayName(using: localization))
                        .font(.system(size: 18, weight: .semibold))
                    Text(target.trigger.displayName(using: localization))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    Spacer()
                    Toggle(
                        "button_mapping.action.disable_switch",
                        isOn: Binding(
                            get: {
                                mappingConfiguration(
                                    for: target.button,
                                    trigger: target.trigger
                                ).action == .disabled
                            },
                            set: { disabled in
                                let key = "\(settings.selectedRemoteProfileID?.uuidString ?? "base"):\(editingMappingProfileID?.uuidString ?? "base"):\(target.id)"
                                let current = mappingConfiguration(for: target.button, trigger: target.trigger)
                                if disabled { disabledMappingBackups[key] = current }
                                let replacement = MappingDisablePolicy.configuration(
                                    disabling: disabled, current: current,
                                    backup: disabledMappingBackups[key], button: target.button,
                                    trigger: target.trigger
                                )
                                saveMappingBinding(replacement, button: target.button, trigger: target.trigger)
                                shortcutCaptureTarget = nil
                                applicationShortcutCaptureProfileID = nil
                            }
                        )
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .tint(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(
                        target.button == .power &&
                            target.trigger == .singleClick &&
                            settings.experimentalContinuousRecordingEnabled
                    )
                    Button("common.action.close") {
                        mappingEditingTarget = nil
                        shortcutCaptureTarget = nil
                        applicationShortcutCaptureProfileID = nil
                    }
                    .compatibilityButtonStyle(.standard)
                }

                mappingTriggerEditor(target.button, trigger: target.trigger)
            }
        }
    }

    private func mappingFooter(includeSiriScrollArrow: Bool = false) -> some View {
        // 能力一律取自「链路自报优先、型号默认兜底」的判定结果（见 RemoteVoiceCapabilities）。
        let capabilities = model.selectedRemoteVoiceCapabilities
        return GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                mappingHIDStatus
                Divider()
                mappingSelectionLockControl
                Divider()
                // 触摸面（滑动箭头/光标）只有具备触摸面的遥控器才显示，页面请求之外再加一道能力门禁。
                if TouchSurfaceControlApplicability.isApplicable(
                    capabilities: capabilities,
                    pageRequestsControl: includeSiriScrollArrow
                ) {
                    Divider()
                    siriRemoteScrollArrowControl
                }
                HStack {
                    Spacer(minLength: 0)
                    mappingRestoreDefaultsButton
                }
            }
        }
    }

    private var siriRemoteScrollArrowControl: some View {
        Toggle(isOn: $settings.siriRemoteScrollArrowReversed) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localization.text("siri_remote.scroll_arrow.reverse.title"))
                    .font(.system(size: 13, weight: .medium))
                Text(localization.text("siri_remote.scroll_arrow.reverse.detail"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .help(localization.text("siri_remote.scroll_arrow.reverse.help"))
    }

    private var mappingHIDStatus: some View {
        Label(
            model.hidStatus.text(using: localization),
            systemImage: "keyboard"
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }

    private var mappingSelectionLockControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("button_mapping.selection_lock", isOn: $isMappingSelectionLocked)
                .font(.system(size: 12, weight: .medium))
                .toggleStyle(.switch)
            Text("button_mapping.selection_lock_hint_short")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .help(localization.text("button_mapping.selection_lock_help"))
    }

    var mappingVoiceKeyModeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("connection.voice_key_mode.title")
                .font(.system(size: 12, weight: .medium))
            Picker("connection.voice_key_mode.title", selection: Binding(
                get: { settings.voiceKeyMode },
                set: { model.setVoiceKeyMode($0) }
            )) {
                ForEach(VoiceKeyMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.localizationKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .tint(Color.accentColor)
            Text("connection.voice_key_mode.help")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if settings.voiceKeyMode != .function {
                Text("connection.voice_key_mode.unverified_detail")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(localization.text("connection.voice_key_mode.help"))
    }

    var mappingVoiceFnTapControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("connection.voice_fn_tap.enabled", isOn: Binding(
                get: { settings.voiceFnTapModeEnabled },
                set: { model.setVoiceFnTapModeEnabled($0) }
            ))
            .font(.system(size: 12, weight: .medium))
            .toggleStyle(.switch)
            Text("connection.voice_fn_tap.hint_short")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .help(localization.text("connection.voice_fn_tap.hint"))
        .opacity(settings.voiceKeyMode == .function ? 1 : 0.55)
        .disabled(settings.voiceKeyMode != .function)
    }

    private var mappingRestoreDefaultsButton: some View {
        Button("common.action.restore_defaults") {
            if let profile = editingMappingProfileID {
                for button in RemoteButton.allCases {
                    for trigger in ButtonTrigger.allCases {
                        macroFeature.setProfileBinding(nil, profile: profile, button: button, trigger: trigger)
                    }
                }
            } else { settings.resetBindings() }
            selectedRemoteButton = .ok
        }
        .compatibilityButtonStyle(.standard)
    }

    private var mappingDevicePicker: some View {
        let profiles = RemoteDeviceNamePolicy.sortedForCards(
            settings.remoteDeviceProfiles,
            modelName: remoteModelName,
            systemName: { model.systemDeviceName(for: $0) }
        )
        return Picker("remote.device.selector", selection: Binding<UUID?>(
            get: { settings.selectedRemoteProfileID },
            set: { if let id = $0 { model.selectRemoteProfile(id) } }
        )) {
            if profiles.isEmpty || settings.selectedRemoteProfileID == nil {
                Text("remote.device.select_placeholder").tag(Optional<UUID>.none)
            }
            ForEach(profiles) { profile in
                Text(remoteModelName(profile)).tag(Optional(profile.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 310)
        .disabled(profiles.isEmpty)
    }
}
