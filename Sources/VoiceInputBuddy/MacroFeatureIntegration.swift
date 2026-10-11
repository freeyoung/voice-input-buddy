import Combine
import SwiftUI


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


    init(localeIdentifier: String = Locale.current.identifier) {
    }

    var hasPendingPortableImport: Bool {
        return false
    }

    var libraryActions: [ButtonLibraryAction] {
        []
    }

    func mappingProfiles(device: UUID?) -> [ButtonMappingProfile] {
        []
    }

    func prepareMappingDevice(_ device: UUID?) {
    }

    func activeMappingProfileID(device: UUID?) -> UUID? {
        nil
    }

    func profileBinding(device: UUID?, profile: UUID? = nil, button: RemoteButton,
                        trigger: ButtonTrigger) -> ConfiguredButtonAction? {
        return nil
    }

    func setProfileBinding(_ configured: ConfiguredButtonAction?, profile: UUID,
                           button: RemoteButton, trigger: ButtonTrigger, displayName: String? = nil) {
    }

    func executeMacro(id: String?) -> Bool {
        return false
    }

    func configurePortableTransfer(settings: AppSettings, beforeApply: @escaping (Data) throws -> Void) {
    }

    func portableTransferView(profileID: UUID?, model: XiaomiRemoteModel?, applicationsOnly: Bool = false) -> AnyView {
        return AnyView(EmptyView())
    }

    func attachBindings(to settings: AppSettings, onProfileChange: @escaping (UUID?) -> Void) {
        settings.configuredActionOverride = { [weak self, weak settings] device, button, trigger in
            guard let settings, settings.customMappingEnabled else { return nil }
            return self?.profileBinding(device: device, button: button, trigger: trigger)
        }
    }


    var sectionTitle: String {
        ""
    }

    var sectionSystemImage: String {
        "command.square"
    }

    var buttonProfilesSectionTitle: String {
        ""
    }

    var buttonProfilesSectionSystemImage: String {
        "rectangle.3.group"
    }

    func updateLocaleIdentifier(_ identifier: String) {
    }

    func refreshAccessIfNeeded(force: Bool = false) {
    }

    func updateButtonProfilesAccess(_ decision: HostButtonProfilesAccessDecision) {
    }

    func setEditorActive(_ active: Bool) {
        isBindingEditorActive = active && (isFeatureVisible || isButtonProfilesVisible)
        isEditorActive = isBindingEditorActive || isPortableEditorActive
    }

    func revealEnrollment() {
    }

    func settingsView(
        selectedRemoteProfileID: UUID?,
        remoteModel: XiaomiRemoteModel?,
        configuredActionTitle: @escaping (String, String) -> String?,
        settings: AppSettings? = nil,
        onEditBinding: @escaping (UUID?, UUID?, RemoteButton, ButtonTrigger) -> Void = { _, _, _, _ in },
        onBindToButton: @escaping () -> Void = {}
    ) -> AnyView {

        AnyView(EmptyView())
    }

    func enrollmentView() -> AnyView {
        AnyView(EmptyView())
    }

    func buttonProfilesView(
        selectedRemoteProfileID: UUID?,
        remoteModel: XiaomiRemoteModel?,
        hostActionSections: [ButtonProfileHostActionSection],
        onEditKeys: @escaping (UUID) -> Void = { _ in },
        chromecastReservedControlIDs: Set<String> = ["left", "right", "select"],
        membershipNotice: AnyView = AnyView(EmptyView())
    ) -> AnyView {
        return AnyView(EmptyView())
    }


    func hasActiveBinding(profileID: UUID?, button: RemoteButton, trigger: ButtonTrigger) -> Bool {
        return false
    }

    func noteButtonInteraction(button: RemoteButton) {
    }

    @discardableResult
    func executeBoundMacro(
        profileID: UUID?,
        button: RemoteButton,
        trigger: ButtonTrigger
    ) -> Bool {
        false
    }

    @discardableResult
    func executeBoundAction(profileID: UUID?, button: RemoteButton, trigger: ButtonTrigger,
                           hostActionPerformer: (Data) -> Bool,
                           shortcutPerformer: (UInt16, [String]) -> Bool,
                            exactShortcutPerformer: ((UInt16,[String],UInt64) -> Bool)? = nil) -> Bool {
        return executeBoundMacro(profileID: profileID, button: button, trigger: trigger)
    }

    func stop() {
    }
}
