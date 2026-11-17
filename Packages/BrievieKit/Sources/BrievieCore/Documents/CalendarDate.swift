import Foundation

/// A day without a time or time zone: a letter's date, a deadline. Never shifted by the device's time zone.
public struct CalendarDate: Equatable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// From `YYYY-MM-DD`; `nil` for anything else, including a day that does not exist.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: Self.utcCalendar) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `timeZone` (for a date the user picked on this device).
    public init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Noon of this day in `timeZone`: for date pickers and formatting in that same time zone.
    public func date(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The same day `years` later (earlier when negative); February 29 becomes February 28 in a year without it.
    public func adding(years: Int) -> CalendarDate {
        let year = year + years
        return CalendarDate(year: year, month: month, day: min(day, Self.daysIn(month: month, year: year)))
    }

    /// The day `days` later (earlier when negative), on the Gregorian calendar.
    public func adding(days: Int) -> CalendarDate {
        var result = self
        var remaining = days
        while remaining > 0 {
            let left = Self.daysIn(month: result.month, year: result.year) - result.day
            if remaining <= left {
                return CalendarDate(year: result.year, month: result.month, day: result.day + remaining)
            }
            remaining -= left + 1
            result = result.month == 12
                ? CalendarDate(year: result.year + 1, month: 1, day: 1)
                : CalendarDate(year: result.year, month: result.month + 1, day: 1)
        }
        while remaining < 0 {
            if -remaining < result.day {
                return CalendarDate(year: result.year, month: result.month, day: result.day + remaining)
            }
            remaining += result.day
            let month = result.month == 1 ? 12 : result.month - 1
            let year = result.month == 1 ? result.year - 1 : result.year
            result = CalendarDate(year: year, month: month, day: Self.daysIn(month: month, year: year))
        }
        return result
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
