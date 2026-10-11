import Combine
import SwiftUI


final class PrivateFeatureIntegration: ObservableObject {
    @Published private(set) var isFeatureVisible = false
    @Published private(set) var shouldShowEnrollment = false
    @Published private(set) var hudShouldBeVisible = false


    init(localeIdentifier: String = Locale.current.identifier) {
    }

    var sectionTitle: String {
        ""
    }

    var isAvailable: Bool {
        false
    }

    var sectionSystemImage: String {
        "sparkles"
    }

    func updateLocaleIdentifier(_ identifier: String) {
    }

    func settingsView() -> AnyView {
        AnyView(EmptyView())
    }

    func enrollmentView() -> AnyView {
        AnyView(EmptyView())
    }

    func refreshAccessIfNeeded(force: Bool = false) {
    }

    func revealEnrollment() {
    }

    func startVoiceSession() {
    }

    func finishVoiceSession() {
    }

    func stop() {
    }

    @MainActor
    func setHUDVisible(_ visible: Bool) {
    }

    @MainActor
    func hideHUDImmediately() {
    }
}
