import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteCore
import BuddyRemoteUI
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    func sectionTitle(_ section: SettingsSection) -> String {
        switch section {
        case .privateFeature: privateFeature.sectionTitle
        case .macros: macroFeature.sectionTitle
        case .buttonProfiles: macroFeature.buttonProfilesSectionTitle
        case .membership: membershipFeature.sectionTitle
        default: ""
        }
    }

    func sectionSystemImage(_ section: SettingsSection) -> String {
        switch section {
        case .privateFeature: privateFeature.sectionSystemImage
        case .macros: macroFeature.sectionSystemImage
        case .buttonProfiles: macroFeature.buttonProfilesSectionSystemImage
        case .membership: membershipFeature.sectionSystemImage
        default: section.systemImage
        }
    }

    @ViewBuilder
    var updateInformationContent: some View {
        switch updateInformation.state {
        case .idle:
            Text("about.version.information_title")
                .font(.headline)
            Text("about.version.information_idle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .checking:
            Text("about.version.information_title")
                .font(.headline)
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("about.version.checking")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("about.version.up_to_date", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("about.version.up_to_date_description")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .unavailable:
            Label("about.version.information_unavailable", systemImage: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("about.version.information_unavailable_description")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case let .available(update):
            Text(String(
                format: localization.text("about.version.release_notes_title"),
                locale: localization.locale,
                arguments: [update.displayVersion]
            ))
            .font(.headline)

            if update.releaseNotes.isEmpty {
                Text("about.version.release_notes_unavailable")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(update.releaseNotes.enumerated()), id: \.offset) { index, note in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(note)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "BuddyReleaseVersion") as? String) ??
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ??
            localization.text("common.value.unknown")
    }

    func revealPrivateEnrollmentIfNeeded() {
        guard versionTapRevealCounter.registerTap() else { return }
        privateFeature.revealEnrollment()
        macroFeature.revealEnrollment()
    }

    func languageTitle(_ language: AppLanguage) -> String {
        language == .system ? localization.text("language.system") : language.nativeDisplayName
    }

    private func buttonPressCountText(for period: UsageStatisticsPeriod) -> String {
        localizedNumber(settings.usageStatistics(for: period).buttonPressCount)
    }

    private func voiceDurationText(for period: UsageStatisticsPeriod) -> String {
        let statistics = settings.usageStatistics(for: period)
        let totalSeconds = max(
            0,
            Int(min(statistics.voiceDuration.rounded(), Double(Int.max)))
        )
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(
                format: localization.text("usage.duration.hours_minutes"),
                locale: localization.locale,
                arguments: [localizedNumber(UInt64(hours)), localizedNumber(UInt64(minutes))]
            )
        }
        if minutes > 0 {
            return String(
                format: localization.text("usage.duration.minutes_seconds"),
                locale: localization.locale,
                arguments: [localizedNumber(UInt64(minutes)), localizedNumber(UInt64(seconds))]
            )
        }
        return String(
            format: localization.text("usage.duration.seconds"),
            locale: localization.locale,
            arguments: [localizedNumber(UInt64(seconds))]
        )
    }

    private func localizedNumber(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = localization.locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
