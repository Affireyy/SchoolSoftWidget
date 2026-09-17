import Foundation

public struct LunchMenu: Codable, Sendable, Equatable {
    public var days: [LunchDay]
    public var lastUpdated: Date?

    public init(days: [LunchDay], lastUpdated: Date? = .now) {
        self.days = days
        self.lastUpdated = lastUpdated
    }

    /// The menu for a specific calendar day, if one was synced.
    public func menu(for date: Date, calendar: Calendar = .current) -> LunchDay? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// A realistic sample week of menus, anchored to the current week (Mon–Fri).
    public static var sample: LunchMenu {
        let calendar = Calendar.current
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let today = calendar.startOfDay(for: .now)
        let weekStart = weekCalendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        let dishesByDay: [(normal: String, vegetarian: String)] = [
            ("Fish gratin with potatoes", "Chickpea stew"),
            ("Meatballs with mashed potatoes & lingonberries", "Bean bolognese"),
            ("Chicken curry with rice", "Vegetable curry"),
            ("Pasta with tomato sauce", "Pasta with tomato sauce"),
            ("Taco buffet", "Bean taco buffet")
        ]

        let days: [LunchDay] = (0..<5).compactMap { offset in
            guard let date = weekCalendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let pair = dishesByDay[offset]
            return LunchDay(date: date, normalDishes: [pair.normal], vegetarianDishes: [pair.vegetarian])
        }

        return LunchMenu(days: days, lastUpdated: .now)
    }
}

public struct LunchDay: Codable, Identifiable, Sendable, Equatable {
    public var date: Date
    /// The non-vegetarian ("Lunch") dishes for this day, straight from
    /// SchoolSoft's `dishCategoryName: "Lunch"` menu.
    public var normalDishes: [String]
    /// The vegetarian dishes for this day, from SchoolSoft's
    /// `dishCategoryName: "Vegetarisk"` menu.
    ///
    /// SchoolSoft sends these as two entirely separate weekly menu objects
    /// for the *same* week (one per `dishCategoryName`), each with its own
    /// per-weekday dish text -- not as a single flagged list. The service
    /// layer (`SchoolSoftScheduleService.retrieveLunch`) merges same-date
    /// entries from both into one `LunchDay` before this is ever stored.
    public var vegetarianDishes: [String]

    public var id: Date { date }

    public init(date: Date, normalDishes: [String] = [], vegetarianDishes: [String] = []) {
        self.date = date
        self.normalDishes = normalDishes
        self.vegetarianDishes = vegetarianDishes
    }

    /// The dishes to show for the given menu mode. When a day only has one
    /// category synced (or the school doesn't distinguish at all), the
    /// other mode falls back to showing it too rather than going blank.
    public func dishes(for mode: LunchMenuMode) -> [String] {
        switch mode {
        case .normal:
            return normalDishes.isEmpty ? vegetarianDishes : normalDishes
        case .vegetarian:
            return vegetarianDishes.isEmpty ? normalDishes : vegetarianDishes
        }
    }
}

/// Which alternative to show when a day's menu lists more than one dish.
/// Stored in the shared cache (see ScheduleCache.lunchMenuMode) so the app
/// and the widget agree on it.
public enum LunchMenuMode: String, CaseIterable, Identifiable, Sendable {
    case normal = "Normal"
    case vegetarian = "Vegetarian"

    public var id: String { rawValue }
}
