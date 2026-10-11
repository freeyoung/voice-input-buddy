import Combine
import SwiftUI

#if canImport(VoiceInputBuddyAI)
import VoiceInputBuddyAI
#endif

final class PrivateFeatureIntegration: ObservableObject {
    @Published private(set) var isFeatureVisible = false
    @Published private(set) var shouldShowEnrollment = false
    @Published private(set) var hudShouldBeVisible = false

#if canImport(VoiceInputBuddyAI)
    private let feature: VoiceInputBuddyAIFeature
    private var hudController: VoiceInputBuddyAIHUDController?
    private var subscriptions = Set<AnyCancellable>()
    private var enrollmentRevealRequested = false
#endif

    init(localeIdentifier: String = Locale.current.identifier) {
        #if canImport(VoiceInputBuddyAI)
        feature = VoiceInputBuddyAIFeature(
            localeIdentifier: localeIdentifier,
            logger: { AppLogger.shared.write($0) }
        )
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
        feature.$hudShouldBeVisible
            .removeDuplicates()
            .assign(to: &$hudShouldBeVisible)
        #endif
    }

    var sectionTitle: String {
        #if canImport(VoiceInputBuddyAI)
        feature.sectionTitle
        #else
        ""
        #endif
    }

    var isAvailable: Bool {
        #if canImport(VoiceInputBuddyAI)
        true
        #else
        false
        #endif
    }

    var sectionSystemImage: String {
        #if canImport(VoiceInputBuddyAI)
        feature.sectionSystemImage
        #else
        "sparkles"
        #endif
    }

    func updateLocaleIdentifier(_ identifier: String) {
        #if canImport(VoiceInputBuddyAI)
        feature.updateLocaleIdentifier(identifier)
        objectWillChange.send()
        #endif
    }

    func settingsView() -> AnyView {
        #if canImport(VoiceInputBuddyAI)
        AnyView(VoiceInputBuddyAISettingsView(feature: feature))
        #else
        AnyView(EmptyView())
        #endif
    }

    func enrollmentView() -> AnyView {
        #if canImport(VoiceInputBuddyAI)
        AnyView(VoiceInputBuddyAIEnrollmentView(feature: feature))
        #else
        AnyView(EmptyView())
        #endif
    }

    func refreshAccessIfNeeded(force: Bool = false) {
#if canImport(VoiceInputBuddyAI)
        feature.refreshAccessIfNeeded(force: force)
#endif
    }

    func revealEnrollment() {
#if canImport(VoiceInputBuddyAI)
        enrollmentRevealRequested = true
        shouldShowEnrollment = true
#endif
    }

    func startVoiceSession() {
        #if canImport(VoiceInputBuddyAI)
        feature.startVoiceSession()
        #endif
    }

    func finishVoiceSession() {
        #if canImport(VoiceInputBuddyAI)
        feature.finishVoiceSession()
        #endif
    }

    func stop() {
        #if canImport(VoiceInputBuddyAI)
        feature.stop()
        #endif
    }

    @MainActor
    func setHUDVisible(_ visible: Bool) {
        #if canImport(VoiceInputBuddyAI)
        if visible {
            let controller = hudController ?? VoiceInputBuddyAIHUDController(feature: feature)
            hudController = controller
            controller.setVisible(true)
        } else {
            hudController?.setVisible(false)
        }
        #endif
    }

    @MainActor
    func hideHUDImmediately() {
        #if canImport(VoiceInputBuddyAI)
        hudController?.hideImmediately()
        #endif
    }
}
