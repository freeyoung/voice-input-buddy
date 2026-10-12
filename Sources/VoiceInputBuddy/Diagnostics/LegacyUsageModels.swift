import Combine
import Foundation

enum UsageStatisticsPeriod: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case total

    var id: String { rawValue }
}

struct UsageStatistics: Equatable {
    let buttonPressCount: UInt64
    let voiceDuration: TimeInterval
}

struct UsageStatisticsBucket: Equatable, Identifiable {
    let startDate: Date
    let statistics: UsageStatistics

    var id: Date { startDate }
}

struct WeeklyUsageStatisticsSeries: Equatable {
    let earlierStatistics: UsageStatistics
    let weeklyBuckets: [UsageStatisticsBucket]
}

enum UsageEventSource: String, Codable, CaseIterable, Hashable {
    case bluetoothRemote = "bluetooth_remote"
    case nearbyPhone = "nearby_phone"
    case webRemote = "web_remote"
    case unknown
}

enum UsageControl {
    case remoteButton(RemoteButton)
    case voice

    var identifier: String {
        switch self {
        case let .remoteButton(button): return "button.\(button.rawValue)"
        case .voice: return "voice"
        }
    }
}

struct UsageStatisticsMetadata: Equatable {
    var firstActivityAt: Date?
    var lastActivityAt: Date?
    var buttonPressCountBySource: [UsageEventSource: UInt64] = [:]
    var buttonPressCountByControl: [String: UInt64] = [:]
    var buttonPressCountByHour: [Int: UInt64] = [:]
    var voiceSessionCount: UInt64 = 0
    var voiceSessionCountBySource: [UsageEventSource: UInt64] = [:]
    var voiceSessionCountByEndHour: [Int: UInt64] = [:]
    var voiceDurationBySource: [UsageEventSource: TimeInterval] = [:]
    var voiceDurationByEndHour: [Int: TimeInterval] = [:]
    var longestVoiceSessionDuration: TimeInterval = 0
    var longestVoiceSessionDurationBySource: [UsageEventSource: TimeInterval] = [:]
    var timeZoneIdentifiers: Set<String> = []
    var calendarIdentifiers: Set<String> = []
    var schemaVersions: Set<Int> = []
}

struct VoiceSessionUsageRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date?
    let endedAt: Date
    let duration: TimeInterval
    let source: UsageEventSource?
    let applicationName: String?

    init(
        id: UUID,
        startedAt: Date?,
        endedAt: Date,
        duration: TimeInterval,
        source: UsageEventSource?,
        applicationName: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.source = source
        self.applicationName = applicationName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case endedAt
        case duration
        case source
        case applicationName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        source = try container.decodeIfPresent(UsageEventSource.self, forKey: .source)
        applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
    }
}

struct DailyUsageMetadata: Codable {
    var schemaVersion = 0
    var firstActivityAt: Date?
    var lastActivityAt: Date?
    var buttonPressCountBySource: [String: UInt64] = [:]
    var buttonPressCountByControl: [String: UInt64] = [:]
    var buttonPressCountByHour: [Int: UInt64] = [:]
    var voiceSessionCount: UInt64 = 0
    var voiceSessionCountBySource: [String: UInt64] = [:]
    var voiceSessionCountByEndHour: [Int: UInt64] = [:]
    var voiceDurationBySource: [String: TimeInterval] = [:]
    var voiceDurationByEndHour: [Int: TimeInterval] = [:]
    var longestVoiceSessionDuration: TimeInterval = 0
    var longestVoiceSessionDurationBySource: [String: TimeInterval] = [:]
    var timeZoneIdentifiers: Set<String> = []
    var calendarIdentifiers: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case firstActivityAt
        case lastActivityAt
        case buttonPressCountBySource
        case buttonPressCountByControl
        case buttonPressCountByHour
        case voiceSessionCount
        case voiceSessionCountBySource
        case voiceSessionCountByEndHour
        case voiceDurationBySource
        case voiceDurationByEndHour
        case longestVoiceSessionDuration
        case longestVoiceSessionDurationBySource
        case timeZoneIdentifiers
        case calendarIdentifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        firstActivityAt = try container.decodeIfPresent(Date.self, forKey: .firstActivityAt)
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt)
        buttonPressCountBySource = try container.decodeIfPresent(
            [String: UInt64].self,
            forKey: .buttonPressCountBySource
        ) ?? [:]
        buttonPressCountByControl = try container.decodeIfPresent(
            [String: UInt64].self,
            forKey: .buttonPressCountByControl
        ) ?? [:]
        buttonPressCountByHour = try container.decodeIfPresent(
            [Int: UInt64].self,
            forKey: .buttonPressCountByHour
        ) ?? [:]
        voiceSessionCount = try container.decodeIfPresent(
            UInt64.self,
            forKey: .voiceSessionCount
        ) ?? 0
        voiceSessionCountBySource = try container.decodeIfPresent(
            [String: UInt64].self,
            forKey: .voiceSessionCountBySource
        ) ?? [:]
        voiceSessionCountByEndHour = try container.decodeIfPresent(
            [Int: UInt64].self,
            forKey: .voiceSessionCountByEndHour
        ) ?? [:]
        voiceDurationBySource = try container.decodeIfPresent(
            [String: TimeInterval].self,
            forKey: .voiceDurationBySource
        ) ?? [:]
        voiceDurationByEndHour = try container.decodeIfPresent(
            [Int: TimeInterval].self,
            forKey: .voiceDurationByEndHour
        ) ?? [:]
        longestVoiceSessionDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .longestVoiceSessionDuration
        ) ?? 0
        longestVoiceSessionDurationBySource = try container.decodeIfPresent(
            [String: TimeInterval].self,
            forKey: .longestVoiceSessionDurationBySource
        ) ?? [:]
        timeZoneIdentifiers = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .timeZoneIdentifiers
        ) ?? []
        calendarIdentifiers = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .calendarIdentifiers
        ) ?? []
    }
}

struct DailyUsageStatistics: Codable {
    var buttonPressCount: UInt64 = 0
    var voiceDuration: TimeInterval = 0
    var metadata = DailyUsageMetadata()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case buttonPressCount
        case voiceDuration
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buttonPressCount = try container.decodeIfPresent(
            UInt64.self,
            forKey: .buttonPressCount
        ) ?? 0
        voiceDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .voiceDuration
        ) ?? 0
        metadata = try container.decodeIfPresent(
            DailyUsageMetadata.self,
            forKey: .metadata
        ) ?? DailyUsageMetadata()
    }
}
