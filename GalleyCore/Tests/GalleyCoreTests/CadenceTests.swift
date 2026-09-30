import Foundation
import Testing
@testable import GalleyCore

struct CadenceTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Ulaanbaatar")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func dailyClosesAtNextMidnight() {
        let close = Cadence.daily.nextClose(after: date(2026, 9, 30, 14, 5), calendar: calendar)
        #expect(close == date(2026, 10, 1))
    }

    @Test func dailyAtMidnightMovesToFollowingDay() {
        let close = Cadence.daily.nextClose(after: date(2026, 10, 1), calendar: calendar)
        #expect(close == date(2026, 10, 2))
    }

    @Test func weeklyClosesOnChosenWeekday() {
        // 30 Sep 2026 is a Wednesday; the next Sunday is 4 Oct.
        let close = Cadence.weekly(weekday: 1).nextClose(after: date(2026, 9, 30, 9), calendar: calendar)
        #expect(close == date(2026, 10, 4))
    }

    @Test func weeklyOnTheSameWeekdayWaitsAWeek() {
        let close = Cadence.weekly(weekday: 1).nextClose(after: date(2026, 10, 4, 8), calendar: calendar)
        #expect(close == date(2026, 10, 11))
    }

    @Test func monthlyClosesOnChosenDay() {
        #expect(Cadence.monthly(day: 1).nextClose(after: date(2026, 9, 30, 23), calendar: calendar) == date(2026, 10, 1))
        #expect(Cadence.monthly(day: 15).nextClose(after: date(2026, 9, 30), calendar: calendar) == date(2026, 10, 15))
        #expect(Cadence.monthly(day: 15).nextClose(after: date(2026, 9, 10), calendar: calendar) == date(2026, 9, 15))
    }

    @Test func manualNeverCloses() {
        #expect(Cadence.manual.nextClose(after: .now, calendar: calendar) == nil)
    }

    @Test func settingsValuesAreClamped() {
        #expect(Cadence(kind: .weekly, weekday: 9, monthDay: 1) == .weekly(weekday: 7))
        #expect(Cadence(kind: .monthly, weekday: 1, monthDay: 31) == .monthly(day: 28))
    }

    @Test func monthlyOnTheFirstIsLabelledByMonth() {
        let label = Cadence.monthly(day: 1).dateLabel(start: date(2026, 10, 1), end: date(2026, 11, 1), calendar: calendar)
        #expect(label.contains("October"))
        #expect(label.contains("2026"))
    }

    @Test func sameDayRangeIsASingleDate() {
        let label = Cadence.weekly(weekday: 1).dateLabel(start: date(2026, 9, 30, 9), end: date(2026, 9, 30, 17), calendar: calendar)
        #expect(label == date(2026, 9, 30).formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: calendar.locale!, calendar: calendar, timeZone: calendar.timeZone)))
    }

    @Test func weeklyLabelShowsTheLastDayNotTheClosingMidnight() {
        let label = Cadence.weekly(weekday: 1).dateLabel(start: date(2026, 9, 27), end: date(2026, 10, 4), calendar: calendar)
        #expect(label.contains("27"))
        #expect(label.contains("3"))
        #expect(!label.contains("4 Oct"))
    }
}

struct ExtractionHelperTests {
    @Test func bylinesAreCleaned() {
        #expect(ArticleExtractor.cleanByline("By  Jane   Doe") == "Jane Doe")
        #expect(ArticleExtractor.cleanByline("   ") == nil)
    }

    @Test func publishedDatesParse() {
        #expect(ArticleExtractor.parseDate("2025-05-27T14:02:11.000Z") != nil)
        #expect(ArticleExtractor.parseDate("2025-05-27T14:02:11+08:00") != nil)
        #expect(ArticleExtractor.parseDate("2025-05-27") != nil)
        #expect(ArticleExtractor.parseDate("last Tuesday") == nil)
    }
}
