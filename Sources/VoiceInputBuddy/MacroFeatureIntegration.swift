import Combine
#if SAYALL_CHROMECAST_ENABLED && canImport(VoiceInputBuddyChromecast)
import VoiceInputBuddyChromecast
#endif
import SwiftUI

#if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
import VoiceInputBuddyMacroCore
import VoiceInputBuddyMacroVoiceInputBuddy
#endif
#if canImport(VoiceInputBuddyButtonProfiles)
import VoiceInputBuddyButtonProfiles
#endif
#if SAYALL_SIRI_REMOTE_ENABLED && canImport(VoiceInputBuddySiriRemote)
import VoiceInputBuddySiriRemote
#endif

struct ButtonProfileHostAction: Equatable {
    let id: String
    let title: String
    let detail: String?
    let systemImage: String
    let payload: Data
    let isAvailable: Bool
}

struct ButtonProfileHostActionSection: Equatable {
    let id: String
    let title: String
    let actions: [ButtonProfileHostAction]
}

final class MacroFeatureIntegration: ObservableObject {
    @Published private(set) var isFeatureVisible = false
    @Published private(set) var isButtonProfilesVisible = false
    @Published private(set) var shouldShowEnrollment = false
    @Published private(set) var isEditorActive = false
    private var subscriptions = Set<AnyCancellable>()
    private var enrollmentRevealRequested = false
    private var isPortableEditorActive = false
    private var isBindingEditorActive = false

#if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
    private let feature: VoiceInputBuddyMacroVoiceInputBuddyFeature
#endif
#if canImport(VoiceInputBuddyButtonProfiles)
    private let buttonProfilesFeature: VoiceInputBuddyButtonProfilesFeature
#endif

    init(localeIdentifier: String = Locale.current.identifier) {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature = VoiceInputBuddyMacroVoiceInputBuddyFeature(localeIdentifier: localeIdentifier)
        #endif
#if canImport(VoiceInputBuddyButtonProfiles)
        buttonProfilesFeature = VoiceInputBuddyButtonProfilesFeature(
            localeIdentifier: localeIdentifier
        )
#endif
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.$isFeatureVisible
            .removeDuplicates()
            .assign(to: &$isFeatureVisible)
        feature.$shouldShowEnrollment
            .removeDuplicates()
            .sink { [weak self] value in
                guard let self else { return }
                self.shouldShowEnrollment = value || self.enrollmentRevealRequested
            }
            .store(in: &subscriptions)
        #endif
#if canImport(VoiceInputBuddyButtonProfiles)
        isButtonProfilesVisible = true
        buttonProfilesFeature.$isButtonProfileBindingEditorActive
            .removeDuplicates()
            .sink { [weak self] active in
                self?.setEditorActive(active)
            }
            .store(in: &subscriptions)
#endif
    }

    var hasPendingPortableImport: Bool {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        return feature.portableTransfer.hasPendingImport
        #else
        return false
        #endif
    }

    var libraryActions: [ButtonLibraryAction] {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        feature.libraryActions.map { ButtonLibraryAction(id: $0.id, name: $0.name, stepCount: $0.stepCount) }
        #else
        []
        #endif
    }

    func mappingProfiles(device: UUID?) -> [ButtonMappingProfile] {
        #if canImport(VoiceInputBuddyButtonProfiles) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        buttonProfilesFeature.profiles(for: device).map { ButtonMappingProfile(id: $0.id, name: buttonProfilesFeature.profileDisplayName($0)) }
        #else
        []
        #endif
    }

    func prepareMappingDevice(_ device: UUID?) {
        #if canImport(VoiceInputBuddyButtonProfiles) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        buttonProfilesFeature.prepareMappingDevice(device)
        #endif
    }

    func activeMappingProfileID(device: UUID?) -> UUID? {
        #if canImport(VoiceInputBuddyButtonProfiles) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        buttonProfilesFeature.activeProfileID(for: device)
        #else
        nil
        #endif
    }

    func profileBinding(device: UUID?, profile: UUID? = nil, button: RemoteButton,
                        trigger: ButtonTrigger) -> ConfiguredButtonAction? {
        #if canImport(VoiceInputBuddyButtonProfiles) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        guard let binding = buttonProfilesFeature.binding(device: device, profile: profile,
            button: button.rawValue, trigger: trigger.rawValue) else { return nil }
        switch binding {
        case let .host(reference):
            // Corrupt or unknown explicit bindings are consumed, never inherited.
            return (try? JSONDecoder().decode(ConfiguredButtonAction.self, from: reference.payload)) ?? .disabled
        case let .macro(reference):
            return ConfiguredButtonAction(action: .combinationAction, shortcut: nil, macroID: reference.macroID)
        case let .shortcut(key):
            guard let shortcut = buttonProfilesFeature.shortcut(id: key) else { return .disabled }
            var flags = NSEvent.ModifierFlags(rawValue: UInt(shortcut.deviceModifierFlags ?? 0))
            for modifier in shortcut.modifiers {
                switch modifier {
                case "command": flags.insert(.command)
                case "shift": flags.insert(.shift)
                case "option": flags.insert(.option)
                case "control": flags.insert(.control)
                case "function": flags.insert(.function)
                default: return .disabled
                }
            }
            return ConfiguredButtonAction(action: .customShortcut,
                shortcut: CustomKeyboardShortcut(keyCode: shortcut.keyCode, modifierFlags: flags, keyLabel: ""))
        }
        #else
        return nil
        #endif
    }

    func setProfileBinding(_ configured: ConfiguredButtonAction?, profile: UUID,
                           button: RemoteButton, trigger: ButtonTrigger, displayName: String? = nil) {
        #if canImport(VoiceInputBuddyButtonProfiles) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        let binding: VoiceInputBuddyButtonProfileBinding?
        if let configured {
            if configured.action == .combinationAction, let id = configured.macroID,
               let version = feature.savedMacroVersion(id: id) {
                binding = .macro(MacroReference(macroID: id, version: version))
            } else {
                guard let data = try? JSONEncoder().encode(configured) else { return }
                binding = .host(VoiceInputBuddyHostActionReference(id: "host.action.\(configured.action.rawValue)",
                    displayName: displayName ?? configured.action.rawValue, payload: data))
            }
        } else { binding = nil }
        buttonProfilesFeature.setBinding(binding, profile: profile, button: button.rawValue, trigger: trigger.rawValue)
        #endif
    }

    func executeMacro(id: String?) -> Bool {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        guard let id else { return false }
        let accepted = feature.executeMacro(id: id)
        AppLogger.shared.write("BUTTON ACTION phase=\(accepted ? "submitted" : "failed") result=\(accepted ? "accepted" : "unavailable_or_busy")")
        return accepted
        #else
        return false
        #endif
    }

    func configurePortableTransfer(settings: AppSettings, beforeApply: @escaping (Data) throws -> Void) {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.portableTransfer.hostAdapter = settings.portableHostAdapter(beforeApply: beforeApply)
        #if SAYALL_UNIFIED_BUTTON_CONFIGURATION
        feature.portableTransfer.exportMacroBindings = nil
        feature.portableTransfer.prepareMacroBindings = nil
        #endif
        feature.portableTransfer.$isPresenting.sink { [weak self] active in
            guard let self else { return }
            self.isPortableEditorActive = active
            self.isEditorActive = active || self.isBindingEditorActive
        }.store(in: &subscriptions)
        feature.portableTransfer.logEvent = { AppLogger.shared.write($0) }
        #if canImport(VoiceInputBuddyButtonProfiles)
        buttonProfilesFeature.configurePortableTransfer(feature.portableTransfer)
        #endif
        do { try feature.portableTransfer.recover() }
        catch { AppLogger.shared.write("TRANSFER RECOVERY phase=failed result=recovery_required") }
        #endif
    }

    func portableTransferView(profileID: UUID?, model: XiaomiRemoteModel?, applicationsOnly: Bool = false) -> AnyView {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        return feature.portableTransferView(selectedRemoteProfileID: profileID,
            remoteModel: AppSettings.portableRemoteModel(model), applicationsOnly: applicationsOnly)
        #else
        return AnyView(EmptyView())
        #endif
    }

    func attachBindings(to settings: AppSettings, onProfileChange: @escaping (UUID?) -> Void) {
        settings.configuredActionOverride = { [weak self, weak settings] device, button, trigger in
            guard let settings, settings.customMappingEnabled else { return nil }
            return self?.profileBinding(device: device, button: button, trigger: trigger)
        }
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        feature.executionEvents.receive(on: DispatchQueue.main).sink { event in
            AppLogger.shared.write("MACRO ACTION operation_id=\(event.0) phase=\(event.1) result=\(event.2) elapsed_ms=\(event.3)")
        }.store(in: &subscriptions)
        feature.changes.receive(on: DispatchQueue.main).sink { [weak self, weak settings] in
            guard let self, let settings else { return }
            DispatchQueue.main.async {
                guard self.feature.hasLoadedLibrary else { return }
                let legacy = self.feature.legacyBindings.compactMap { value -> UnifiedButtonBinding? in
                    guard let button = RemoteButton(rawValue: value.button),
                          let trigger = ButtonTrigger(rawValue: value.trigger) else { return nil }
                    return UnifiedButtonBinding(remoteProfileID: value.device, button: button, trigger: trigger,
                        configured: ConfiguredButtonAction(action: .combinationAction, shortcut: nil, macroID: value.macroID))
                }
                do { try settings.migrateLegacyMacroBindings(legacy) }
                catch { AppLogger.shared.write("BUTTON CONFIGURATION phase=failed result=migration_backup_failed") }
                self.objectWillChange.send()
            }
        }.store(in: &subscriptions)
        #endif
        #if canImport(VoiceInputBuddyButtonProfiles) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
        var lastActiveProfiles: [UUID?: UUID] = [:]
        buttonProfilesFeature.changes.receive(on: DispatchQueue.main).sink { [weak self, weak settings] in
            DispatchQueue.main.async {
                guard let self, let settings else { return }
                let devices: [UUID?] = [nil] + settings.remoteDeviceProfiles.map { Optional($0.id) }
                for device in devices {
                    let active = self.activeMappingProfileID(device: device)
                    if active != lastActiveProfiles[device] {
                        lastActiveProfiles[device] = active
                        onProfileChange(device)
                    }
                }
                self.objectWillChange.send()
                settings.objectWillChange.send()
            }
        }.store(in: &subscriptions)
        #endif
    }

    #if canImport(VoiceInputBuddyMacroVoiceInputBuddy) && SAYALL_UNIFIED_BUTTON_CONFIGURATION
    private func bindingUsages(_ settings: AppSettings) -> [VoiceInputBuddyBindingUsage] {
        let localization = LocalizationStore(settings: settings)
        func deviceName(_ id: UUID?) -> String {
            guard let profile = settings.remoteDeviceProfiles.first(where: { $0.id == id }) else {
                return localization.text("button_mapping.base_profile")
            }
            return RemoteDeviceNamePolicy.displayName(for: profile, among: settings.remoteDeviceProfiles,
                defaultName: localization.text(profile.displayNameFallbackKey))
        }
        var usages = settings.unifiedBaseBindings.compactMap { binding -> VoiceInputBuddyBindingUsage? in
            guard binding.configured.action == .combinationAction, let id = binding.configured.macroID else { return nil }
            return VoiceInputBuddyBindingUsage(
                id: "base.\(binding.remoteProfileID?.uuidString ?? "default").\(binding.button.rawValue).\(binding.trigger.rawValue)",
                macroID: id, title: deviceName(binding.remoteProfileID) + " · " + localization.text("button_mapping.base_profile") + " · " + binding.button.displayName(using: localization) + " · " + binding.trigger.displayName(using: localization),
                device: binding.remoteProfileID, profile: nil, button: binding.button.rawValue, trigger: binding.trigger.rawValue)
        }
        #if canImport(VoiceInputBuddyButtonProfiles)
        for profile in buttonProfilesFeature.allProfiles {
            for (key, binding) in profile.bindings {
                let id: String?
                switch binding {
                case let .macro(reference): id = reference.macroID
                case let .host(reference):
                    let configured = try? JSONDecoder().decode(ConfiguredButtonAction.self, from: reference.payload)
                    id = configured?.action == .combinationAction ? configured?.macroID : nil
                case .shortcut: id = nil
                }
                guard let id else { continue }
                usages.append(VoiceInputBuddyBindingUsage(id: "\(profile.id).\(key.button.rawValue).\(key.trigger.rawValue)",
                    macroID: id, title: deviceName(profile.remoteProfileID) + " · " + buttonProfilesFeature.profileDisplayName(profile) + " · " + (RemoteButton(rawValue: key.button.rawValue)?.displayName(using: localization) ?? key.button.rawValue) + " · " + (ButtonTrigger(rawValue: key.trigger.rawValue)?.displayName(using: localization) ?? key.trigger.rawValue),
                    device: profile.remoteProfileID, profile: profile.id, button: key.button.rawValue, trigger: key.trigger.rawValue))
            }
        }
        #endif
        return usages
    }
    #endif

    var sectionTitle: String {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.sectionTitle
        #else
        ""
        #endif
    }

    var sectionSystemImage: String {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.sectionSystemImage
        #else
        "command.square"
        #endif
    }

    var buttonProfilesSectionTitle: String {
        #if canImport(VoiceInputBuddyButtonProfiles)
        buttonProfilesFeature.buttonProfilesSectionTitle
        #else
        ""
        #endif
    }

    var buttonProfilesSectionSystemImage: String {
        #if canImport(VoiceInputBuddyButtonProfiles)
        buttonProfilesFeature.buttonProfilesSectionSystemImage
        #else
        "rectangle.3.group"
        #endif
    }

    func updateLocaleIdentifier(_ identifier: String) {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.updateLocaleIdentifier(identifier)
        objectWillChange.send()
        #endif
        #if canImport(VoiceInputBuddyButtonProfiles)
        buttonProfilesFeature.updateLocaleIdentifier(identifier)
        objectWillChange.send()
        #endif
    }

    func refreshAccessIfNeeded(force: Bool = false) {
#if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.refreshAccessIfNeeded(force: force)
#endif
#if canImport(VoiceInputBuddyButtonProfiles)
        buttonProfilesFeature.refreshAccessIfNeeded(force: force)
#endif
    }

    func updateButtonProfilesAccess(_ decision: HostButtonProfilesAccessDecision) {
        #if canImport(VoiceInputBuddyButtonProfiles)
        #if SAYALL_TEST_BUTTON_PROFILES_FREE
        buttonProfilesFeature.updateButtonProfilesAccess(
            .allowed(validUntil: .distantFuture)
        )
        #else
        let packageDecision: ButtonProfilesAccessDecision
        switch decision {
        case let .allowed(validUntil):
            packageDecision = .allowed(validUntil: validUntil)
        case let .temporarilyOffline(validUntil):
            packageDecision = .temporarilyOffline(validUntil: validUntil)
        case .requiresPlus:
            packageDecision = .requiresPlus
        case .unavailable:
            packageDecision = .unavailable
        }
        buttonProfilesFeature.updateButtonProfilesAccess(packageDecision)
        #endif
        #endif
    }

    func setEditorActive(_ active: Bool) {
        isBindingEditorActive = active && (isFeatureVisible || isButtonProfilesVisible)
        isEditorActive = isBindingEditorActive || isPortableEditorActive
    }

    func revealEnrollment() {
#if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        enrollmentRevealRequested = true
        shouldShowEnrollment = true
#endif
    }

    func settingsView(
        selectedRemoteProfileID: UUID?,
        remoteModel: XiaomiRemoteModel?,
        configuredActionTitle: @escaping (String, String) -> String?,
        settings: AppSettings? = nil,
        onEditBinding: @escaping (UUID?, UUID?, RemoteButton, ButtonTrigger) -> Void = { _, _, _, _ in },
        onBindToButton: @escaping () -> Void = {}
    ) -> AnyView {
        #if SAYALL_UNIFIED_BUTTON_CONFIGURATION && canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        return feature.settingsView(
            selectedRemoteProfileID: selectedRemoteProfileID,
            remotePresentation: combinationActionsRemotePresentation(for: remoteModel),
            configuredActionTitle: configuredActionTitle,
            usages: settings.map(bindingUsages) ?? [],
            onEditBinding: { usage in
                guard let button = RemoteButton(rawValue: usage.button),
                      let trigger = ButtonTrigger(rawValue: usage.trigger) else { return }
                onEditBinding(usage.device, usage.profile, button, trigger)
            },
            onBindToButton: onBindToButton)
        #else

        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        #if SAYALL_MACRO_REMOTE_CAPABILITIES
        feature.settingsView(
            selectedRemoteProfileID: selectedRemoteProfileID,
            remotePresentation: combinationActionsRemotePresentation(for: remoteModel),
            configuredActionTitle: configuredActionTitle,
            onBindingEditorActivityChanged: { [weak self] active in
                self?.setEditorActive(active)
            }
        )
        #else
        feature.settingsView(
            selectedRemoteProfileID: selectedRemoteProfileID,
            configuredActionTitle: configuredActionTitle,
            onBindingEditorActivityChanged: { [weak self] active in
                self?.setEditorActive(active)
            }
        )
        #endif
        #else
        AnyView(EmptyView())
        #endif
        #endif
    }

    func enrollmentView() -> AnyView {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.enrollmentView()
        #else
        AnyView(EmptyView())
        #endif
    }

    func buttonProfilesView(
        selectedRemoteProfileID: UUID?,
        remoteModel: XiaomiRemoteModel?,
        hostActionSections: [ButtonProfileHostActionSection],
        onEditKeys: @escaping (UUID) -> Void = { _ in },
        chromecastReservedControlIDs: Set<String> = ["left", "right", "select"],
        membershipNotice: AnyView = AnyView(EmptyView())
    ) -> AnyView {
        #if canImport(VoiceInputBuddyButtonProfiles)
        #if SAYALL_MACRO_REMOTE_CAPABILITIES
        return buttonProfilesFeature.buttonProfilesView(
            selectedRemoteProfileID: selectedRemoteProfileID,
            remotePresentation: buttonProfilesRemotePresentation(for: remoteModel, chromecastReservedControlIDs: chromecastReservedControlIDs),
            hostActionSections: hostActionSections.map { section in
                VoiceInputBuddyHostActionSection(
                    id: section.id,
                    title: section.title,
                    actions: section.actions.map { action in
                        VoiceInputBuddyHostActionDescriptor(
                            reference: VoiceInputBuddyHostActionReference(
                                id: action.id,
                                displayName: action.title,
                                payload: action.payload
                            ),
                            detail: action.detail,
                            systemImage: action.systemImage,
                            isAvailable: action.isAvailable
                        )
                    }
                )
            },
            membershipNotice: membershipNotice
        )
        #else
        return buttonProfilesFeature.buttonProfilesView(
            selectedRemoteProfileID: selectedRemoteProfileID,
            hostActionSections: hostActionSections.map { section in
                VoiceInputBuddyHostActionSection(
                    id: section.id,
                    title: section.title,
                    actions: section.actions.map { action in
                        VoiceInputBuddyHostActionDescriptor(
                            reference: VoiceInputBuddyHostActionReference(
                                id: action.id,
                                displayName: action.title,
                                payload: action.payload
                            ),
                            detail: action.detail,
                            systemImage: action.systemImage,
                            isAvailable: action.isAvailable
                        )
                    }
                )
            }
        )
        #endif
        #else
        return AnyView(EmptyView())
        #endif
    }

    #if SAYALL_MACRO_REMOTE_CAPABILITIES && canImport(VoiceInputBuddyMacroVoiceInputBuddy)
    private func combinationActionsRemotePresentation(
        for model: XiaomiRemoteModel?
    ) -> VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemotePresentation {
        switch model {
        case .rc001:
            return VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemotePresentation.xiaomiRC001(displayName: "RC001")
        case .rc003, .unknown, nil:
            return VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemotePresentation.xiaomiRC003(displayName: "RC003")
        case .chromecastVoiceRemote:
            #if SAYALL_CHROMECAST_ENABLED && canImport(VoiceInputBuddyChromecast)
            let anchors = Dictionary(uniqueKeysWithValues: ChromecastMappingCanvas.placements.compactMap { placement in
                VoiceInputBuddyMacroButton(rawValue: placement.controlID == "select" ? "ok" : placement.controlID)
                    .map { ($0, placement.anchor) }
            })
            return VoiceInputBuddyRemotePresentation(
                capabilities: VoiceInputBuddyRemoteModelCatalog.capabilities(for: VoiceInputBuddyRemoteModelID.chromecastVoiceRemote)!,
                displayName: "Chromecast Voice Remote", image: ChromecastMappingCanvas.remoteImage,
                aspectRatio: ChromecastMappingCanvas.remoteSize.width / ChromecastMappingCanvas.remoteSize.height,
                anchors: anchors)
            #else
            return VoiceInputBuddyRemotePresentation(
                capabilities: VoiceInputBuddyRemoteModelCatalog.capabilities(for: VoiceInputBuddyRemoteModelID.chromecastVoiceRemote)!,
                displayName: "Chromecast Voice Remote", image: nil, aspectRatio: 155.0 / 510.0, anchors: [:])
            #endif
        case .appleSiriRemoteA2854, .appleSiriRemoteA2540:
            #if SAYALL_SIRI_REMOTE_ENABLED && canImport(VoiceInputBuddySiriRemote)
            let siriModel: VoiceInputBuddySiriRemoteModel = model == .appleSiriRemoteA2540
                ? .a2540
                : .a2854
            let source = VoiceInputBuddySiriRemoteDevicePresentation.presentation(for: siriModel)
            let capabilities = VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemoteModelCatalog.capabilities(
                for: source.model.stableModelID
            )!
            let anchors = Dictionary(uniqueKeysWithValues: source.anchors.compactMap {
                controlID, anchor in
                combinationActionsMacroButton(forSiriControlID: controlID).map { ($0, anchor) }
            })
            return VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemotePresentation(
                capabilities: capabilities,
                displayName: source.displayName,
                image: source.image,
                aspectRatio: source.aspectRatio,
                anchors: anchors
            )
            #else
            let modelID = model == .appleSiriRemoteA2540
                ? VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemoteModelID.appleSiriRemoteA2540
                : VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemoteModelID.appleSiriRemoteA2854
            return VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemotePresentation(
                capabilities: VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyRemoteModelCatalog.capabilities(for: modelID)!,
                displayName: "Siri Remote",
                image: nil,
                aspectRatio: 423.0 / 1510.0,
                anchors: [:]
            )
            #endif
        }
    }

    private func combinationActionsMacroButton(
        forSiriControlID controlID: String
    ) -> VoiceInputBuddyMacroVoiceInputBuddy.VoiceInputBuddyMacroButton? {
        switch controlID {
        case "power": .power
        case "up": .up
        case "left": .left
        case "select": .ok
        case "right": .right
        case "down": .down
        case "back": .back
        case "tv": .tv
        case "play_pause": .playPause
        case "volume_up": .volumeUp
        case "mute": .mute
        case "volume_down": .volumeDown
        default: nil
        }
    }

    #if canImport(VoiceInputBuddyButtonProfiles)
    private func buttonProfilesRemotePresentation(
        for model: XiaomiRemoteModel?,
        chromecastReservedControlIDs: Set<String>
    ) -> VoiceInputBuddyButtonProfiles.VoiceInputBuddyRemotePresentation {
        let source = combinationActionsRemotePresentation(for: model)
        guard model == .chromecastVoiceRemote else { return source }
        let reserved = Set(chromecastReservedControlIDs.compactMap {
            VoiceInputBuddyMacroButton(rawValue: $0 == "select" ? "ok" : $0)
        })
        return VoiceInputBuddyRemotePresentation(
            capabilities: VoiceInputBuddyRemoteCapabilities(modelID: source.capabilities.modelID,
                configurableButtons: VoiceInputBuddyRemoteModelCatalog.chromecastButtons, reservedButtons: reserved),
            displayName: source.displayName, image: source.image,
            aspectRatio: source.aspectRatio, anchors: source.anchors)
    }
    #endif
    #endif

    func hasActiveBinding(profileID: UUID?, button: RemoteButton, trigger: ButtonTrigger) -> Bool {
        #if SAYALL_UNIFIED_BUTTON_CONFIGURATION
        return false
        #else
        #if canImport(VoiceInputBuddyButtonProfiles)
        if buttonProfilesFeature.hasActiveBinding(remoteProfileID: profileID, button: button.rawValue, trigger: trigger.rawValue) { return true }
        #endif
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        return feature.hasActiveBinding(remoteProfileID: profileID, button: button.rawValue, trigger: trigger.rawValue)
        #else
        return false
        #endif
        #endif
    }

    func noteButtonInteraction(button: RemoteButton) {
#if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.noteButtonInteraction(button: button.rawValue)
#endif
#if canImport(VoiceInputBuddyButtonProfiles)
        buttonProfilesFeature.noteButtonInteraction(button: button.rawValue)
#endif
    }

    @discardableResult
    func executeBoundMacro(
        profileID: UUID?,
        button: RemoteButton,
        trigger: ButtonTrigger
    ) -> Bool {
        #if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.executeBoundMacro(
            remoteProfileID: profileID,
            button: button.rawValue,
            trigger: trigger.rawValue
        )
        #else
        false
        #endif
    }

    @discardableResult
    func executeBoundAction(profileID: UUID?, button: RemoteButton, trigger: ButtonTrigger,
                           hostActionPerformer: (Data) -> Bool,
                           shortcutPerformer: (UInt16, [String]) -> Bool,
                            exactShortcutPerformer: ((UInt16,[String],UInt64) -> Bool)? = nil) -> Bool {
        #if SAYALL_UNIFIED_BUTTON_CONFIGURATION
        return false
        #else
        #if canImport(VoiceInputBuddyButtonProfiles)
        if buttonProfilesFeature.executeBoundAction(remoteProfileID: profileID, button: button.rawValue,
            trigger: trigger.rawValue, hostActionPerformer: hostActionPerformer, shortcutPerformer: shortcutPerformer,
            exactShortcutPerformer: exactShortcutPerformer) { return true }
        #endif
        return executeBoundMacro(profileID: profileID, button: button, trigger: trigger)
        #endif
    }

    func stop() {
#if canImport(VoiceInputBuddyMacroVoiceInputBuddy)
        feature.stop()
#endif
#if canImport(VoiceInputBuddyButtonProfiles)
        buttonProfilesFeature.stop()
#endif
    }
}
