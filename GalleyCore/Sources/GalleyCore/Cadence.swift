import Foundation

/// How often an edition closes. An edition collects articles until its period
/// ends, then it is laid out and ready to print.
public enum Cadence: Hashable, Sendable {
    case daily
    /// Closes at midnight at the start of `weekday` (1 = Sunday … 7 = Saturday).
    case weekly(weekday: Int)
    /// Closes at midnight at the start of `day` (1…28) each month.
    case monthly(day: Int)
    /// Closes only when you say so.
    case manual

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case daily, weekly, monthly, manual
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            case .manual: "Manual"
            }
        }
    }

    public static let `default` = Cadence.weekly(weekday: 1)

    public var kind: Kind {
        switch self {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .manual: .manual
        }
    }

    public init(kind: Kind, weekday: Int, monthDay: Int) {
        switch kind {
        case .daily: self = .daily
        case .weekly: self = .weekly(weekday: min(max(weekday, 1), 7))
        case .monthly: self = .monthly(day: min(max(monthDay, 1), 28))
        case .manual: self = .manual
        }
    }

    /// The first moment after `date` at which an open edition closes, or nil for manual.
    public func nextClose(after date: Date, calendar: Calendar = .current) -> Date? {
        var components = DateComponents(hour: 0, minute: 0, second: 0)
        switch self {
        case .daily: break
        case .weekly(let weekday): components.weekday = weekday
        case .monthly(let day): components.day = day
        case .manual: return nil
        }
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
    }

    /// A short description for settings and the sidebar, e.g. "Weekly on Sunday".
    public func summary(calendar: Calendar = .current) -> String {
        switch self {
        case .daily: return "Every day at midnight"
        case .weekly(let weekday): return "Weekly on \(calendar.weekdaySymbols[weekday - 1])"
        case .monthly(let day): return "Monthly on the \(Self.ordinal(day))"
        case .manual: return "When you close it"
        }
    }

    /// The dateline printed on an edition covering `start` up to (not including) `end`.
    public func dateLabel(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let lastDay = calendar.date(byAdding: .second, value: -1, to: end) ?? end
        switch self {
        case .daily:
            return start.formatted(.dateTime.day().month(.wide).year())
        case .monthly(let day) where day == 1:
            return start.formatted(.dateTime.month(.wide).year())
        case .weekly, .monthly:
            return Self.range(start, lastDay, calendar: calendar)
        case .manual:
            if calendar.isDate(start, inSameDayAs: lastDay) {
                return start.formatted(.dateTime.day().month(.wide).year())
            }
            return Self.range(start, lastDay, calendar: calendar)
        }
    }

    /// "27 Sep – 3 Oct 2026" (or the local equivalent); a single day if both fall on it.
    static func range(_ a: Date, _ b: Date, calendar: Calendar) -> String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: a, to: max(a, b))
    }

    static func ordinal(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: n as NSNumber) ?? "\(n)"
    }
}
