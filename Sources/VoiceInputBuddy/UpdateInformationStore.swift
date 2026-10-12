import Combine
import Foundation

struct AvailableUpdateInformation: Equatable {
    let displayVersion: String
    let buildVersion: String
    let releaseNotes: [String]
}

enum UpdateInformationState: Equatable {
    case idle
    case checking
    case upToDate
    case unavailable
    case available(AvailableUpdateInformation)
}

enum UpdateFeedResolutionError: Error {
    case invalidResponse
}

enum UpdateFeedResolver {
    struct ResolvedFeed: Equatable {
        let url: URL
        let version: String
        let isPreRelease: Bool
    }

    struct FeedResolution: Equatable {
        let stable: ResolvedFeed?
        let preview: ResolvedFeed?

        var selected: ResolvedFeed? {
            UpdateFeedResolver.preferredFeed(stable: stable, preview: preview)
        }
    }

    typealias FeedDataLoader = @Sendable (URL) async throws -> Data

    private static let maximumFeedSize = 1 * 1_024 * 1_024

    static func testInjectedFeed(
        environment: [String: String],
        assetName: String,
        includePreRelease: Bool
    ) -> ResolvedFeed? {
        guard environment["VOICE_INPUT_BUDDY_UI_TEST_MODE"] == "1",
              includePreRelease,
              let rawURL = environment["VOICE_INPUT_BUDDY_UI_TEST_FEED_URL"],
              let url = URL(string: rawURL),
              url.scheme == "http",
              url.host == "127.0.0.1",
              url.port != nil,
              ["appcast-arm64.xml", "appcast-intel.xml"].contains(url.lastPathComponent),
              url.lastPathComponent == assetName,
              let rawVersion = environment["VOICE_INPUT_BUDDY_UI_TEST_VERSION"],
              let version = UpdateVersion.normalized(rawVersion)
        else { return nil }
        return ResolvedFeed(url: url, version: version, isPreRelease: true)
    }

    static func preferredFeed(
        stable: ResolvedFeed?,
        preview: ResolvedFeed?
    ) -> ResolvedFeed? {
        switch (stable, preview) {
        case let (stable?, preview?):
            return UpdateVersion.isNewer(preview.version, than: stable.version)
                ? preview
                : stable
        case let (stable?, nil):
            return stable
        case let (nil, preview?):
            return preview
        case (nil, nil):
            return nil
        }
    }

    static func resolvePreviewFeed(
        stableURL: URL,
        previewURL: URL,
        loader: @escaping FeedDataLoader = { url in
            try await UpdateFeedResolver.loadFeedData(from: url)
        }
    ) async -> FeedResolution {
        async let stableData = try? loader(stableURL)
        async let previewData = try? loader(previewURL)
        let (stablePayload, previewPayload) = await (stableData, previewData)
        return FeedResolution(
            stable: stablePayload.flatMap {
                resolvedFeed(url: stableURL, data: $0, isPreRelease: false)
            },
            preview: previewPayload.flatMap {
                resolvedFeed(url: previewURL, data: $0, isPreRelease: true)
            }
        )
    }

    private static func loadFeedData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("VoiceInputBuddy", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              data.count <= maximumFeedSize
        else {
            throw UpdateFeedResolutionError.invalidResponse
        }
        return data
    }

    private static func resolvedFeed(
        url: URL,
        data: Data,
        isPreRelease: Bool
    ) -> ResolvedFeed? {
        guard let text = String(data: data, encoding: .utf8),
              let version = highestAppcastVersion(in: text)
        else { return nil }
        return ResolvedFeed(url: url, version: version, isPreRelease: isPreRelease)
    }

    private static func highestAppcastVersion(in text: String) -> String? {
        let pattern = #"<sparkle:shortVersionString>\s*([^<]+?)\s*</sparkle:shortVersionString>"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let versions = expression.matches(in: text, range: range).compactMap { match -> String? in
            guard let versionRange = Range(match.range(at: 1), in: text) else { return nil }
            return UpdateVersion.normalized(String(text[versionRange]))
        }
        return versions.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return UpdateVersion.isNewer(candidate, than: current) ? candidate : current
        }
    }

}

enum UpdateVersion {
    static func normalized(_ rawValue: String) -> String? {
        let stripped = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let value = stripped.range(of: #"^\d{2}-\d{2}-\d{2}\.\d{3}$"#, options: .regularExpression) != nil
            ? stripped.replacingOccurrences(of: "-", with: ".") : stripped
        guard value.range(of: #"^\d+(?:\.\d+){1,3}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = normalized(candidate),
              let current = normalized(current)
        else { return false }
        let candidateParts = candidate.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(candidateParts.count, currentParts.count)
        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }
}

enum UpdateReleaseNotes {
    static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \Character.isNewline).compactMap { line in
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("- ") || value.hasPrefix("• ") {
                value.removeFirst(2)
            }
            guard !value.isEmpty, !value.hasPrefix("#") else { return nil }
            return value
        }
    }

}

@MainActor
final class UpdateInformationStore: ObservableObject {
    @Published private(set) var state: UpdateInformationState = .idle
    @Published private(set) var hasUnseenUpdate = false

    private struct PendingUpdate: Equatable {
        let displayVersion: String
        let buildVersion: String
        let fallbackNotes: [String]

        var identifier: String {
            "\(displayVersion)|\(buildVersion)"
        }
    }

    private static let lastSeenUpdateIdentifierKey =
        "updateInformation.lastSeenUpdateIdentifier"

    private let userDefaults: UserDefaults
    private var pendingUpdate: PendingUpdate?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func beginChecking() {
        state = .checking
    }

    func reset() {
        pendingUpdate = nil
        state = .idle
        clearUnseenUpdate(reason: "update_state_reset")
    }

    func setUpToDate() {
        pendingUpdate = nil
        state = .upToDate
        clearUnseenUpdate(reason: "up_to_date")
    }

    func setUnavailable() {
        pendingUpdate = nil
        state = .unavailable
        clearUnseenUpdate(reason: "update_information_unavailable")
    }

    func setAvailable(
        displayVersion: String,
        buildVersion: String,
        fallbackDescription: String?
    ) {
        let pending = PendingUpdate(
            displayVersion: displayVersion,
            buildVersion: buildVersion,
            fallbackNotes: fallbackDescription.map(UpdateReleaseNotes.parse) ?? []
        )
        let candidateChanged = pendingUpdate?.identifier != pending.identifier
        pendingUpdate = pending
        state = .available(information(for: pending, notes: pending.fallbackNotes))
        if candidateChanged {
            hasUnseenUpdate = userDefaults.string(
                forKey: Self.lastSeenUpdateIdentifierKey
            ) != pending.identifier
            AppLogger.shared.write(
                "UPDATE BADGE phase=completed result=\(hasUnseenUpdate ? "shown" : "suppressed") " +
                    "reason=\(hasUnseenUpdate ? "new_update_detected" : "already_seen") " +
                    "display_version=\(AppLogger.stableToken(displayVersion)) " +
                    "build_version=\(AppLogger.stableToken(buildVersion))"
            )
        }
    }

    func markAvailableUpdateSeen() {
        guard hasUnseenUpdate, let pendingUpdate else { return }
        userDefaults.set(pendingUpdate.identifier, forKey: Self.lastSeenUpdateIdentifierKey)
        hasUnseenUpdate = false
        AppLogger.shared.write(
            "UPDATE BADGE phase=completed result=cleared reason=settings_opened " +
                "display_version=\(AppLogger.stableToken(pendingUpdate.displayVersion)) " +
                "build_version=\(AppLogger.stableToken(pendingUpdate.buildVersion))"
        )
    }

    private func information(
        for pending: PendingUpdate,
        notes: [String]
    ) -> AvailableUpdateInformation {
        AvailableUpdateInformation(
            displayVersion: pending.displayVersion,
            buildVersion: pending.buildVersion,
            releaseNotes: notes
        )
    }

    private func clearUnseenUpdate(reason: String) {
        guard hasUnseenUpdate else { return }
        hasUnseenUpdate = false
        AppLogger.shared.write(
            "UPDATE BADGE phase=completed result=cleared reason=\(reason)"
        )
    }

}
