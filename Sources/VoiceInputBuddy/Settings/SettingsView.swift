import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteCore
import BuddyRemoteUI
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: BridgeAppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var privateFeature: PrivateFeatureIntegration
    @State var preservesMappingContextOnNavigation = false
    @State var editingMappingProfileID: UUID?
    @State var mappingMacroSearch = ""

    @ObservedObject var macroFeature: MacroFeatureIntegration
    @ObservedObject var membershipFeature: MembershipFeatureIntegration
    @ObservedObject var loginItemService: LoginItemService
    @ObservedObject var updateInformation: UpdateInformationStore
    @EnvironmentObject var localization: LocalizationStore

    let checkForUpdates: () -> Void
    let refreshUpdateInformation: () -> Void
    let setDockIconVisible: (Bool) -> Void
    let setStatusBarIconVisible: (Bool) -> Void
    let syncEntryPointVisibility: () -> Void
    let appIconCatalog: AppIconCatalog
    private let minimumContentSize: CGSize
    let initialShortcutPickerShowsKeyboard: Bool

    @State var selectedSection: SettingsSection
    @State var selectedRemoteButton: RemoteButton = .ok
    @State private var selectedSiriRemoteControlID = "select"
    @State private var selectedChromecastControlID = "select"
    @State var isMappingSelectionLocked = true
    @State var mappingEditingTarget: ShortcutEditingTarget?
    @State var mappingDisableEditor = MappingDisableEditor()
    @State var mappingActionFilter: MappingActionFilter = .all
    @State var shortcutCaptureTarget: ShortcutEditingTarget?
    @State var applicationShortcutCaptureProfileID: UUID?
    @State var shortcutCaptureFeedback: ShortcutCaptureFeedback?
    @State var customApplicationLearningStates: [UUID: CustomApplicationLearningState] = [:]
    @State var bluetoothAuthorization = CBManager.authorization
    @State var inputMonitoringGranted = HIDRemoteMonitor.isInputMonitoringGranted
    @State var accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
    @State var configurationStatus: ConfigurationStatus?
    @State var isRepositoryLinkCopied = false
    @State var isMappingPermissionAlertPresented = false
    @State var isWaitingForMappingPermissions = false
    @State var versionTapRevealCounter = VersionTapRevealCounter()

    init(
        model: BridgeAppModel,
        updateInformation: UpdateInformationStore,
        checkForUpdates: @escaping () -> Void = {},
        refreshUpdateInformation: @escaping () -> Void = {},
        setDockIconVisible: @escaping (Bool) -> Void = { _ in },
        setStatusBarIconVisible: @escaping (Bool) -> Void = { _ in },
        syncEntryPointVisibility: @escaping () -> Void = {},
        appIconCatalog: AppIconCatalog? = nil,
        initialSection: SettingsSection? = nil,
        initialMappingEditingButton: RemoteButton? = nil,
        initialMappingEditingTrigger: ButtonTrigger = .singleClick,
        initialShortcutPickerShowsKeyboard: Bool = false,
        minimumContentSize: CGSize = CGSize(width: 980, height: 732)
    ) {
        self.model = model
        settings = model.settings
        privateFeature = model.privateFeature
        macroFeature = model.macroFeature
        membershipFeature = model.membershipFeature
        loginItemService = model.loginItemService
        self.updateInformation = updateInformation
        self.checkForUpdates = checkForUpdates
        self.refreshUpdateInformation = refreshUpdateInformation
        self.setDockIconVisible = setDockIconVisible
        self.setStatusBarIconVisible = setStatusBarIconVisible
        self.syncEntryPointVisibility = syncEntryPointVisibility
        self.appIconCatalog = appIconCatalog ?? .live()
        self.minimumContentSize = minimumContentSize
        self.initialShortcutPickerShowsKeyboard = initialShortcutPickerShowsKeyboard
        _selectedSection = State(initialValue: SettingsPageBehavior.initialSection(
            requestedSection: initialSection,
            privateFeatureVisible: model.privateFeature.isFeatureVisible,
            macroFeatureVisible: model.macroFeature.isFeatureVisible,
            buttonProfilesVisible: model.macroFeature.isButtonProfilesVisible,
            membershipVisible: model.membershipFeature.isFeatureVisible
        ))
        _selectedRemoteButton = State(initialValue: initialMappingEditingButton ?? .ok)
        _mappingEditingTarget = State(
            initialValue: initialMappingEditingButton.map {
                ShortcutEditingTarget(button: $0, trigger: initialMappingEditingTrigger)
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 108)
            Color(nsColor: .separatorColor)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
            selectedPage
        }
        .background(Color(nsColor: .controlBackgroundColor).ignoresSafeArea())
        .environment(\.locale, localization.locale)
        .environment(\.openURL, OpenURLAction { url in
            guard url == URL(string: "voice-input-buddy://membership") else { return .systemAction }
            guard membershipFeature.isFeatureVisible else { return .discarded }
            selectedSection = .membership
            membershipFeature.refreshIfNeeded()
            return .handled
        })
        .frame(
            minWidth: minimumContentSize.width,
            minHeight: minimumContentSize.height
        )
        .onAppear {
            if selectedSection == .mapping {
                model.selectDefaultMappingRemoteIfAvailable()
            }
            model.refreshRemoteDeviceNames(reason: .page)
            refreshPermissionStates()
            loginItemService.refresh()
            macroFeature.setEditorActive(false)
            membershipFeature.refreshIfNeeded()
        }
        .onChange(of: selectedSection) { _, section in
            if section == .mapping {
                if preservesMappingContextOnNavigation { preservesMappingContextOnNavigation = false }
                else { model.selectDefaultMappingRemoteIfAvailable() }
            }
            if section == .connection || section == .mapping {
                model.refreshRemoteDeviceNames(reason: .page)
            }
            if section != .macros, section != .buttonProfiles {
                macroFeature.setEditorActive(false)
            }
        }
        .onDisappear {
            macroFeature.setEditorActive(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStates()
            loginItemService.refresh()
            resumeCustomMappingIfPermissionsGranted()
            membershipFeature.refreshIfNeeded()
        }
        .onReceive(privateFeature.$isFeatureVisible.removeDuplicates()) { isVisible in
            if !isVisible, selectedSection == .privateFeature {
                selectedSection = .about
            }
        }
        .onReceive(macroFeature.$isFeatureVisible.removeDuplicates()) { isVisible in
            if !isVisible,
               (selectedSection == .macros || selectedSection == .buttonProfiles) {
                selectedSection = .about
            }
        }
        .onReceive(membershipFeature.$isFeatureVisible.removeDuplicates()) { isVisible in
            if !isVisible, selectedSection == .membership {
                selectedSection = .about
            }
        }
        .alert(
            localization.text("button_mapping.permission_prompt.title"),
            isPresented: $isMappingPermissionAlertPresented
        ) {
            Button("button_mapping.permission_prompt.open") {
                isWaitingForMappingPermissions = true
                selectedSection = .permissions
                model.applyHIDSettings()
            }
            Button("common.action.cancel", role: .cancel) {
                settings.customMappingEnabled = false
                model.applyHIDSettings()
            }
        } message: {
            Text("button_mapping.permission_prompt.message")
        }
    }
}
