import AppKit
import Combine
import Sparkle

struct UpdateDialogVersion: Equatable {
    let version: String
    let commitCount: String

    static func current(bundle: Bundle = .main) -> Self {
        Self(version: bundle.object(forInfoDictionaryKey: "BuddyReleaseVersion") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
             commitCount: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
    }

    func text(using localization: LocalizationStore) -> String {
        LocalizedMessage("update.dialog.version", arguments: [version, commitCount]).text(using: localization)
    }
}

/// Sparkle retains responsibility for verification, downloading and installation.
/// Only its public user-interface callbacks are implemented here.
@MainActor
final class LocalizedUpdateUserDriver: NSObject, SPUUserDriver {
    private struct Action {
        let key: String
        let completes: Bool
        let handler: () -> Void
    }

    private let localization: LocalizationStore
    private let currentVersion: UpdateDialogVersion
    private let presentsWindows: Bool
    private var languageSubscription: AnyCancellable?
    private var window: NSWindow?
    private var isPresented = false
    private var candidateVersion: UpdateDialogVersion?
    private var actions: [Action] = []
    private var detailArguments: [String] = []
    private var detailKey = "update.dialog.current"
    private var titleKey = "menu.check_for_updates"
    private var progress: Double?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    var title: String { localization.text(titleKey) }
    var detail: String {
        let versions = [currentVersion.text(using: localization)] +
            (["update.dialog.found.detail", "update.dialog.not_found.latest.detail", "update.dialog.current_and_target"].contains(detailKey) ? [candidateVersion?.text(using: localization) ?? ""] : [])
        return LocalizedMessage(detailKey, arguments: versions + detailArguments).text(using: localization)
    }
    var actionTitles: [String] { actions.map { localization.text($0.key) } }
    var displayedProgress: Double? { progress }

    init(localization: LocalizationStore, currentVersion: UpdateDialogVersion = .current(), presentsWindows: Bool = true) {
        self.localization = localization
        self.currentVersion = currentVersion
        self.presentsWindows = presentsWindows
        super.init()
        languageSubscription = localization.$locale
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
    }

    private func present(_ title: String, detail: String = "update.dialog.current", arguments: [String] = [],
                         progress: Double? = nil, actions: [Action] = []) {
        isPresented = true
        titleKey = title
        detailKey = detail == "update.dialog.current" && candidateVersion != nil ? "update.dialog.current_and_target" : detail
        detailArguments = arguments
        self.progress = progress
        self.actions = actions
        render()
    }

    private func render() {
        guard isPresented, presentsWindows else { return }
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 250),
                                 styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.center()
            window = panel
        }
        guard let window else { return }
        window.title = localization.text("update.dialog.window")
        let heading = NSTextField(wrappingLabelWithString: title)
        heading.font = .systemFont(ofSize: 19, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: detail)
        description.font = .systemFont(ofSize: 13)
        description.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [heading, description])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        for view in [heading, description] {
            view.widthAnchor.constraint(equalToConstant: 412).isActive = true
        }
        if let progress {
            let indicator = NSProgressIndicator()
            indicator.style = .bar
            indicator.isIndeterminate = progress < 0
            indicator.minValue = 0
            indicator.maxValue = 1
            indicator.doubleValue = progress
            indicator.widthAnchor.constraint(equalToConstant: 412).isActive = true
            if indicator.isIndeterminate { indicator.startAnimation(nil) }
            stack.addArrangedSubview(indicator)
        }
        let buttons = NSStackView()
        buttons.spacing = 8
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: localization.text(action.key), target: self, action: #selector(clicked(_:)))
            button.bezelStyle = .rounded
            button.tag = index
            button.keyEquivalent = action.key == "common.action.cancel" ? "\u{1b}" : index == actions.count - 1 ? "\r" : ""
            buttons.addArrangedSubview(button)
        }
        stack.addArrangedSubview(buttons)
        if candidateVersion != nil {
            let history = NSButton(title: localization.text("update.dialog.history"), target: self, action: #selector(openHistory))
            history.bezelStyle = .rounded
            stack.addArrangedSubview(history)
        }
        let content = NSView()
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: max(460, stack.fittingSize.width + 48), height: max(250, stack.fittingSize.height + 48)))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHistory() {
        NSWorkspace.shared.open(AppLinks.githubRepository.appendingPathComponent("releases"))
    }

    @objc private func clicked(_ sender: NSButton) { performAction(at: sender.tag) }

    func performAction(at index: Int) {
        guard actions.indices.contains(index) else { return }
        let action = actions[index]
        if action.completes { dismissUpdateInstallation() }
        action.handler()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        present("update.dialog.permission", detail: "update.dialog.permission.detail", actions: [
            Action(key: "update.dialog.manual_only", completes: true) {
                reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
            },
            Action(key: "update.dialog.allow_checks", completes: true) {
                reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
            },
        ])
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        candidateVersion = nil
        present("update.dialog.checking", progress: -1,
                actions: [Action(key: "common.action.cancel", completes: true, handler: cancellation)])
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        showAvailableUpdate(UpdateDialogVersion(version: appcastItem.displayVersionString, commitCount: appcastItem.versionString), reply: reply)
    }

    func showAvailableUpdate(_ version: UpdateDialogVersion, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        candidateVersion = version
        present("update.dialog.found", detail: "update.dialog.found.detail",
                actions: [
            Action(key: "update.dialog.later", completes: true) { reply(.dismiss) },
            Action(key: "update.dialog.skip", completes: true) { reply(.skip) },
            Action(key: "update.dialog.install", completes: true) { reply(.install) },
        ])
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        // An unavailable compatible update is not necessarily the latest installed version.
        if let item = (error as NSError).userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem {
            candidateVersion = UpdateDialogVersion(version: item.displayVersionString, commitCount: item.versionString)
        } else {
            candidateVersion = nil
        }
        present("update.dialog.not_found", detail: candidateVersion == nil
                    ? "update.dialog.not_found.detail" : "update.dialog.not_found.latest.detail",
                actions: [Action(key: "common.action.ok", completes: true, handler: acknowledgement)])
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let error = error as NSError
        present("update.dialog.error", detail: "update.dialog.error.detail",
                arguments: [error.domain, String(error.code)],
                actions: [Action(key: "common.action.ok", completes: true, handler: acknowledgement)])
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        present("update.dialog.downloading", progress: -1,
                actions: [Action(key: "common.action.cancel", completes: true, handler: cancellation)])
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        updateDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let sum = receivedLength.addingReportingOverflow(length)
        receivedLength = sum.overflow ? UInt64.max : sum.partialValue
        updateDownloadProgress()
    }

    private func updateDownloadProgress() {
        progress = expectedLength > 0 ? min(1, Double(receivedLength) / Double(expectedLength)) : -1
        render()
    }

    func showDownloadDidStartExtractingUpdate() { present("update.dialog.extracting", progress: -1) }
    func showExtractionReceivedProgress(_ progress: Double) { self.progress = min(1, max(0, progress)); render() }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        present("update.dialog.ready", actions: [
            Action(key: "update.dialog.cancel_install", completes: true) { reply(.skip) },
            Action(key: "update.dialog.install_later", completes: true) { reply(.dismiss) },
            Action(key: "update.dialog.install_restart", completes: true) { reply(.install) },
        ])
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        present("update.dialog.installing", progress: -1,
                actions: applicationTerminated ? [] : [Action(key: "update.dialog.retry_quit", completes: false, handler: retryTerminatingApplication)])
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        present("update.dialog.installed", actions: [Action(key: "common.action.ok", completes: true, handler: acknowledgement)])
    }

    func dismissUpdateInstallation() {
        isPresented = false
        actions = []
        window?.orderOut(nil)
        window = nil
    }

    func showUpdateInFocus() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
#if DEBUG
    static func runPreviewIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let stage = environment["VOICE_INPUT_BUDDY_UPDATE_UI_PREVIEW"] else { return false }
        let suite = "voice-input-buddy.update-preview." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { return true }
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = LocalizationStore(settings: AppSettings(defaults: defaults))
        localization.select(environment["VOICE_INPUT_BUDDY_UPDATE_UI_LANGUAGE"] == "en" ? .english : .simplifiedChinese)
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.finishLaunching()
        let driver = LocalizedUpdateUserDriver(localization: localization)
        let stop = { application.stop(nil) }
        switch stage {
        case "found":
            driver.showAvailableUpdate(.init(version: "v26-10-12.073", commitCount: "73")) { _ in stop() }
        case "ready":
            driver.showReady(toInstallAndRelaunch: { _ in stop() })
        case "current":
            driver.showUpdateNotFoundWithError(NSError(domain: "Preview", code: 0), acknowledgement: stop)
        case "error":
            driver.showUpdaterError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), acknowledgement: stop)
        default:
            driver.showUserInitiatedUpdateCheck(cancellation: stop)
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in
            MainActor.assumeIsolated { application.stop(nil) }
        }
        application.run()
        timer.invalidate()
        driver.dismissUpdateInstallation()
        return true
    }
#endif

}
