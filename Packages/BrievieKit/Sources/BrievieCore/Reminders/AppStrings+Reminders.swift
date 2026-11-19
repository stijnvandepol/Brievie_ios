import Foundation

extension AppStrings {
    // The text of a deadline reminder: on the lock screen, outside the app lock. Nothing from the letter; the
    // sender only when the user chose "Toon de afzender in herinneringen".

    static var reminderToday: String {
        String(localized: "reminders.body.today", defaultValue: "Een termijn loopt vandaag af.", bundle: .module)
    }

    static var reminderTomorrow: String {
        String(localized: "reminders.body.tomorrow", defaultValue: "Een termijn loopt morgen af.", bundle: .module)
    }

    /// `%d` is the number of days, at least 2.
    static var reminderInDaysFormat: String {
        String(localized: "reminders.body.days", defaultValue: "Een termijn loopt over %d dagen af.", bundle: .module)
    }

    /// `%@` is the sender.
    static var reminderSenderTodayFormat: String {
        String(
            localized: "reminders.body.sender.today", defaultValue: "Een termijn van %@ loopt vandaag af.",
            bundle: .module
        )
    }

    /// `%@` is the sender.
    static var reminderSenderTomorrowFormat: String {
        String(
            localized: "reminders.body.sender.tomorrow", defaultValue: "Een termijn van %@ loopt morgen af.",
            bundle: .module
        )
    }

    /// `%1$@` is the sender, `%2$d` the number of days (at least 2).
    static var reminderSenderInDaysFormat: String {
        String(
            localized: "reminders.body.sender.days", defaultValue: "Een termijn van %1$@ loopt over %2$d dagen af.",
            bundle: .module
        )
    }

    /// Every reminder text by catalog key, for the parity test.
    static var reminderTexts: [String: String] {
        [
            "reminders.body.today": reminderToday,
            "reminders.body.tomorrow": reminderTomorrow,
            "reminders.body.days": reminderInDaysFormat,
            "reminders.body.sender.today": reminderSenderTodayFormat,
            "reminders.body.sender.tomorrow": reminderSenderTomorrowFormat,
            "reminders.body.sender.days": reminderSenderInDaysFormat
        ]
    }
}
