import Combine
import Foundation

extension AppSettings {
    func recordButtonPress(
        control: UsageControl? = nil,
        source: UsageEventSource = .unknown,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        // Usage statistics are not collected in Voice Input Buddy.
    }

    func recordVoiceDuration(
        _ duration: TimeInterval,
        startedAt: Date? = nil,
        source: UsageEventSource = .unknown,
        applicationName: String? = nil,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        // Usage statistics are not collected in Voice Input Buddy.
    }

    func usageStatistics(
        for period: UsageStatisticsPeriod,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageStatistics {
        switch period {
        case .today:
            return Self.usageStatistics(
                from: dailyStatistics[Self.dayKey(for: date, calendar: calendar)]
            )
        case .thisWeek:
            guard let week = Self.weekInterval(containing: date, calendar: calendar) else {
                return UsageStatistics(buttonPressCount: 0, voiceDuration: 0)
            }
            return usageStatistics(in: week, calendar: calendar)
        case .total:
            return UsageStatistics(
                buttonPressCount: totalButtonPressCount,
                voiceDuration: totalVoiceDuration
            )
        }
    }

    func dailyUsageStatistics(
        endingAt date: Date = Date(),
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [UsageStatisticsBucket] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: date)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return UsageStatisticsBucket(
                startDate: day,
                statistics: Self.usageStatistics(
                    from: dailyStatistics[Self.dayKey(for: day, calendar: calendar)]
                )
            )
        }
    }

    func weeklyUsageStatistics(
        endingAt date: Date = Date(),
        weeks: Int = 8,
        calendar: Calendar = .current
    ) -> [UsageStatisticsBucket] {
        guard
            weeks > 0,
            let currentWeek = Self.weekInterval(containing: date, calendar: calendar)
        else { return [] }

        return (0..<weeks).reversed().compactMap { offset in
            guard
                let start = calendar.date(
                    byAdding: .day,
                    value: -(offset * 7),
                    to: currentWeek.start
                ),
                let end = calendar.date(byAdding: .day, value: 7, to: start)
            else { return nil }
            return UsageStatisticsBucket(
                startDate: start,
                statistics: usageStatistics(
                    in: DateInterval(start: start, end: end),
                    calendar: calendar
                )
            )
        }
    }

    func weeklyUsageStatisticsSeries(
        endingAt date: Date = Date(),
        recentWeeks: Int = 7,
        calendar: Calendar = .current
    ) -> WeeklyUsageStatisticsSeries {
        let weeklyBuckets = weeklyUsageStatistics(
            endingAt: date,
            weeks: recentWeeks,
            calendar: calendar
        )
        let earlierStatistics = weeklyBuckets.first.map { firstBucket in
            usageStatistics(before: firstBucket.startDate, calendar: calendar)
        } ?? UsageStatistics(buttonPressCount: 0, voiceDuration: 0)
        return WeeklyUsageStatisticsSeries(
            earlierStatistics: earlierStatistics,
            weeklyBuckets: weeklyBuckets
        )
    }

    func usageMetadata(
        for period: UsageStatisticsPeriod,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageStatisticsMetadata {
        switch period {
        case .today:
            return Self.usageMetadata(
                from: dailyStatistics[Self.dayKey(for: date, calendar: calendar)]
            )
        case .thisWeek:
            guard let week = Self.weekInterval(containing: date, calendar: calendar) else {
                return UsageStatisticsMetadata()
            }
            return usageMetadata(in: week, calendar: calendar)
        case .total:
            return dailyStatistics.values.reduce(into: UsageStatisticsMetadata()) { result, statistics in
                Self.merge(Self.usageMetadata(from: statistics), into: &result)
            }
        }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func weekInterval(
        containing date: Date,
        calendar: Calendar
    ) -> DateInterval? {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysSinceWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        guard
            let start = calendar.date(byAdding: .day, value: -daysSinceWeekStart, to: startOfDay),
            let end = calendar.date(byAdding: .day, value: 7, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func usageStatistics(
        from daily: DailyUsageStatistics?
    ) -> UsageStatistics {
        UsageStatistics(
            buttonPressCount: daily?.buttonPressCount ?? 0,
            voiceDuration: max(0, daily?.voiceDuration ?? 0)
        )
    }

    private func usageStatistics(
        in interval: DateInterval,
        calendar: Calendar
    ) -> UsageStatistics {
        dailyStatistics.reduce(
            into: UsageStatistics(buttonPressCount: 0, voiceDuration: 0)
        ) { result, entry in
            guard
                let day = Self.date(fromDayKey: entry.key, calendar: calendar),
                day >= interval.start,
                day < interval.end
            else { return }
            result = UsageStatistics(
                buttonPressCount: Self.addingCount(
                    entry.value.buttonPressCount,
                    to: result.buttonPressCount
                ),
                voiceDuration: Self.addingDuration(
                    entry.value.voiceDuration,
                    to: result.voiceDuration
                )
            )
        }
    }

    private func usageStatistics(
        before date: Date,
        calendar: Calendar
    ) -> UsageStatistics {
        dailyStatistics.reduce(
            into: UsageStatistics(buttonPressCount: 0, voiceDuration: 0)
        ) { result, entry in
            guard
                let day = Self.date(fromDayKey: entry.key, calendar: calendar),
                day < date
            else { return }
            result = UsageStatistics(
                buttonPressCount: Self.addingCount(
                    entry.value.buttonPressCount,
                    to: result.buttonPressCount
                ),
                voiceDuration: Self.addingDuration(
                    entry.value.voiceDuration,
                    to: result.voiceDuration
                )
            )
        }
    }

    private static func recordActivityProvenance(
        in metadata: inout DailyUsageMetadata,
        startingAt: Date,
        endingAt: Date,
        calendar: Calendar
    ) {
        let firstDate = min(startingAt, endingAt)
        let lastDate = max(startingAt, endingAt)
        metadata.schemaVersion = 1
        metadata.firstActivityAt = metadata.firstActivityAt.map { min($0, firstDate) } ?? firstDate
        metadata.lastActivityAt = metadata.lastActivityAt.map { max($0, lastDate) } ?? lastDate
        metadata.timeZoneIdentifiers.insert(calendar.timeZone.identifier)
        metadata.calendarIdentifiers.insert(String(describing: calendar.identifier))
    }

    private static func usageMetadata(
        from daily: DailyUsageStatistics?
    ) -> UsageStatisticsMetadata {
        guard let metadata = daily?.metadata else { return UsageStatisticsMetadata() }
        var result = UsageStatisticsMetadata(
            firstActivityAt: metadata.firstActivityAt,
            lastActivityAt: metadata.lastActivityAt,
            buttonPressCountByControl: metadata.buttonPressCountByControl,
            buttonPressCountByHour: metadata.buttonPressCountByHour,
            voiceSessionCount: metadata.voiceSessionCount,
            voiceSessionCountByEndHour: metadata.voiceSessionCountByEndHour,
            voiceDurationByEndHour: metadata.voiceDurationByEndHour,
            longestVoiceSessionDuration: max(0, metadata.longestVoiceSessionDuration),
            timeZoneIdentifiers: metadata.timeZoneIdentifiers,
            calendarIdentifiers: metadata.calendarIdentifiers,
            schemaVersions: metadata.schemaVersion > 0 ? [metadata.schemaVersion] : []
        )
        for (rawSource, count) in metadata.buttonPressCountBySource {
            addCount(
                count,
                for: UsageEventSource(rawValue: rawSource) ?? .unknown,
                to: &result.buttonPressCountBySource
            )
        }
        for (rawSource, count) in metadata.voiceSessionCountBySource {
            addCount(
                count,
                for: UsageEventSource(rawValue: rawSource) ?? .unknown,
                to: &result.voiceSessionCountBySource
            )
        }
        for (rawSource, duration) in metadata.voiceDurationBySource {
            addDuration(
                duration,
                for: UsageEventSource(rawValue: rawSource) ?? .unknown,
                to: &result.voiceDurationBySource
            )
        }
        for (rawSource, duration) in metadata.longestVoiceSessionDurationBySource {
            let source = UsageEventSource(rawValue: rawSource) ?? .unknown
            result.longestVoiceSessionDurationBySource[source] = max(
                result.longestVoiceSessionDurationBySource[source] ?? 0,
                max(0, duration)
            )
        }
        return result
    }

    private func usageMetadata(
        in interval: DateInterval,
        calendar: Calendar
    ) -> UsageStatisticsMetadata {
        dailyStatistics.reduce(into: UsageStatisticsMetadata()) { result, entry in
            guard
                let day = Self.date(fromDayKey: entry.key, calendar: calendar),
                day >= interval.start,
                day < interval.end
            else { return }
            Self.merge(Self.usageMetadata(from: entry.value), into: &result)
        }
    }

    private static func merge(
        _ metadata: UsageStatisticsMetadata,
        into result: inout UsageStatisticsMetadata
    ) {
        if let firstActivityAt = metadata.firstActivityAt {
            result.firstActivityAt = result.firstActivityAt.map {
                min($0, firstActivityAt)
            } ?? firstActivityAt
        }
        if let lastActivityAt = metadata.lastActivityAt {
            result.lastActivityAt = result.lastActivityAt.map {
                max($0, lastActivityAt)
            } ?? lastActivityAt
        }
        for (source, count) in metadata.buttonPressCountBySource {
            addCount(count, for: source, to: &result.buttonPressCountBySource)
        }
        for (control, count) in metadata.buttonPressCountByControl {
            addCount(count, for: control, to: &result.buttonPressCountByControl)
        }
        for (hour, count) in metadata.buttonPressCountByHour {
            addCount(count, for: hour, to: &result.buttonPressCountByHour)
        }
        result.voiceSessionCount = addingCount(
            metadata.voiceSessionCount,
            to: result.voiceSessionCount
        )
        for (source, count) in metadata.voiceSessionCountBySource {
            addCount(count, for: source, to: &result.voiceSessionCountBySource)
        }
        for (hour, count) in metadata.voiceSessionCountByEndHour {
            addCount(count, for: hour, to: &result.voiceSessionCountByEndHour)
        }
        for (source, duration) in metadata.voiceDurationBySource {
            addDuration(duration, for: source, to: &result.voiceDurationBySource)
        }
        for (hour, duration) in metadata.voiceDurationByEndHour {
            addDuration(duration, for: hour, to: &result.voiceDurationByEndHour)
        }
        result.longestVoiceSessionDuration = max(
            result.longestVoiceSessionDuration,
            metadata.longestVoiceSessionDuration
        )
        for (source, duration) in metadata.longestVoiceSessionDurationBySource {
            result.longestVoiceSessionDurationBySource[source] = max(
                result.longestVoiceSessionDurationBySource[source] ?? 0,
                duration
            )
        }
        result.timeZoneIdentifiers.formUnion(metadata.timeZoneIdentifiers)
        result.calendarIdentifiers.formUnion(metadata.calendarIdentifiers)
        result.schemaVersions.formUnion(metadata.schemaVersions)
    }

    private static func addCount<Key: Hashable>(
        _ value: UInt64,
        for key: Key,
        to values: inout [Key: UInt64]
    ) {
        values[key] = addingCount(value, to: values[key] ?? 0)
    }

    private static func addDuration<Key: Hashable>(
        _ duration: TimeInterval,
        for key: Key,
        to values: inout [Key: TimeInterval]
    ) {
        values[key] = addingDuration(duration, to: values[key] ?? 0)
    }

    private static func addingCount(_ value: UInt64, to total: UInt64) -> UInt64 {
        let (result, overflow) = total.addingReportingOverflow(value)
        return overflow ? .max : result
    }

    private static func addingDuration(
        _ duration: TimeInterval,
        to total: TimeInterval
    ) -> TimeInterval {
        let result = max(0, total) + max(0, duration)
        return result.isFinite ? result : .greatestFiniteMagnitude
    }

    static func normalizedVoiceSessionRanking(
        _ records: [VoiceSessionUsageRecord]
    ) -> [VoiceSessionUsageRecord] {
        Array(
            records
                .filter { $0.duration.isFinite && $0.duration > 0 }
                .sorted {
                    if $0.duration == $1.duration {
                        return $0.endedAt > $1.endedAt
                    }
                    return $0.duration > $1.duration
                }
                .prefix(10)
        )
    }

    static let defaultBindings: [RemoteButton: ButtonAction] = [
        .power: .escape,
        .up: .arrowUp,
        .left: .arrowLeft,
        .ok: .returnKey,
        .right: .arrowRight,
        .down: .arrowDown,
        .back: .deleteBackward,
        .volumeUp: .volumeUp,
        .home: .showDesktop,
        .volumeDown: .volumeDown,
        .menu: .contextMenu,
        .tv: .appSwitcher,
        .playPause: .playPause,
        .mute: .volumeMute,
    ]
}
