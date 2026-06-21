import Foundation

/// Hebrew-localized timestamp helpers for the messages UI.
enum ChatTime {
    private static let locale = Locale(identifier: "he_IL")

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        return c
    }

    /// Compact inbox timestamp: today → "HH:mm", yesterday → "אתמול",
    /// within a week → weekday, otherwise a short date.
    static func inboxTimestamp(_ date: Date, now: Date = Date()) -> String {
        let cal = calendar
        if cal.isDateInToday(date) { return timeFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "אתמול" }
        if isWithinWeek(date, now: now, cal: cal) { return weekdayFormatter.string(from: date) }
        return shortDateFormatter.string(from: date)
    }

    /// Day-separator label inside a conversation.
    static func daySeparator(_ date: Date, now: Date = Date()) -> String {
        let cal = calendar
        if cal.isDateInToday(date) { return "היום" }
        if cal.isDateInYesterday(date) { return "אתמול" }
        if isWithinWeek(date, now: now, cal: cal) { return weekdayFormatter.string(from: date) }
        return longDateFormatter.string(from: date)
    }

    /// True if the two dates fall on different calendar days.
    static func isDifferentDay(_ a: Date, _ b: Date) -> Bool {
        !calendar.isDate(a, inSameDayAs: b)
    }

    private static func isWithinWeek(_ date: Date, now: Date, cal: Calendar) -> Bool {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        return days >= 0 && days < 7
    }

    private static let timeFormatter: DateFormatter = formatter("HH:mm")
    private static let weekdayFormatter: DateFormatter = formatter("EEEE")
    private static let shortDateFormatter: DateFormatter = formatter("d.M.yy")
    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f
    }
}
