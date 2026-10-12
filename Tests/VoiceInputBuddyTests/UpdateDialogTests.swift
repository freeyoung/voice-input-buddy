import Foundation
import Sparkle
import Testing
@testable import VoiceInputBuddy

@Suite("Localized update dialogs")
@MainActor
struct UpdateDialogTests {
    private func localization(_ suite: String) throws -> LocalizationStore {
        let defaults = try #require(UserDefaults(suiteName: suite))
        return LocalizationStore(settings: AppSettings(defaults: defaults), resourceBundle: VoiceInputBuddyResourceBundle.mainOrDevelopment)
    }

    @Test func checkingFollowsChosenLanguageAndCancellationIsDeliveredOnce() throws {
        let suite = "update-dialog-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let language = try localization(suite)
        language.select(.english)
        let driver = LocalizedUpdateUserDriver(localization: language,
            currentVersion: .init(version: "v26-10-12.070", commitCount: "70"), presentsWindows: false)
        var cancellations = 0
        driver.showUserInitiatedUpdateCheck { cancellations += 1 }
        #expect(driver.title == "Checking for updates…")
        #expect(driver.detail.contains("Git commits: 70"))
        language.select(.simplifiedChinese)
        #expect(driver.title == "正在检查更新…")
        #expect(driver.detail.contains("Git 提交数：70"))
        #expect(driver.actionTitles == ["取消"])
        driver.performAction(at: 0)
        driver.performAction(at: 0)
        #expect(cancellations == 1)
    }

    @Test func foundVersionAndBuildStayLocalizedAndInstallChoiceIsExplicit() throws {
        let suite = "update-dialog-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let language = try localization(suite)
        language.select(.english)
        let driver = LocalizedUpdateUserDriver(localization: language,
            currentVersion: .init(version: "v26-10-12.070", commitCount: "70"), presentsWindows: false)
        var choices: [SPUUserUpdateChoice] = []
        driver.showAvailableUpdate(.init(version: "v26-10-12.073", commitCount: "73")) { choices.append($0) }
        #expect(driver.detail.contains("v26-10-12.073 (Git commits: 73)"))
        #expect(choices.isEmpty)
        language.select(.simplifiedChinese)
        #expect(driver.detail.contains("v26-10-12.073（Git 提交数：73）"))
        #expect(driver.detail.contains("v26-10-12.070（Git 提交数：70）"))
        driver.performAction(at: 2)
        driver.performAction(at: 2)
        #expect(choices == [.install])
    }

    @Test func errorAcknowledgementUsesAppLanguageAndDoesNotExposeSystemMessage() throws {
        let suite = "update-dialog-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let language = try localization(suite)
        language.select(.simplifiedChinese)
        let driver = LocalizedUpdateUserDriver(localization: language, presentsWindows: false)
        var acknowledgements = 0
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                            userInfo: [NSLocalizedDescriptionKey: "Untranslated system message"])
        driver.showUpdaterError(error) { acknowledgements += 1 }
        #expect(driver.title == "更新未能完成")
        #expect(driver.detail.contains("-1009"))
        #expect(!driver.detail.contains("Untranslated system message"))
        driver.performAction(at: 0)
        driver.performAction(at: 0)
        #expect(acknowledgements == 1)
    }

    @Test func readyUpdateCanBeDeferredWithoutSkippingIt() throws {
        let suite = "update-dialog-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let language = try localization(suite)
        language.select(.english)
        let driver = LocalizedUpdateUserDriver(localization: language, presentsWindows: false)
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        #expect(driver.actionTitles == ["Cancel Installation", "Install Later", "Install and Relaunch"])
        driver.performAction(at: 1)
        driver.performAction(at: 1)
        #expect(choices == [.dismiss])
    }

    @Test func progressHandlesUnknownLengthsAndDismissalDoesNotCancelCompletedDownload() throws {
        let suite = "update-dialog-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let language = try localization(suite)
        let driver = LocalizedUpdateUserDriver(localization: language, presentsWindows: false)
        var cancellations = 0
        driver.showDownloadInitiated { cancellations += 1 }
        #expect(driver.displayedProgress == -1)
        driver.showDownloadDidReceiveExpectedContentLength(100)
        driver.showDownloadDidReceiveData(ofLength: 200)
        #expect(driver.displayedProgress == 1)
        driver.showDownloadDidStartExtractingUpdate()
        #expect(driver.actionTitles.isEmpty)
        driver.dismissUpdateInstallation()
        #expect(cancellations == 0)
    }
}
