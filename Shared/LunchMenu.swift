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

        let dishesByDay: [[String]] = [
            ["Fish gratin with potatoes", "Vegetarian: Chickpea stew"],
            ["Meatballs with mashed potatoes & lingonberries", "Vegetarian: Bean bolognese"],
            ["Chicken curry with rice", "Vegetarian: Vegetable curry"],
            ["Pasta with tomato sauce", "Vegetarian: same"],
            ["Taco buffet", "Vegetarian: Bean taco buffet"]
        ]

        let days: [LunchDay] = (0..<5).compactMap { offset in
            guard let date = weekCalendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return LunchDay(date: date, dishes: dishesByDay[offset])
        }

        return LunchMenu(days: days, lastUpdated: .now)
    }
}

public struct LunchDay: Codable, Identifiable, Sendable, Equatable {
    public var date: Date
    public var dishes: [String]

    public var id: Date { date }

    public init(date: Date, dishes: [String]) {
        self.date = date
        self.dishes = dishes
    }

    /// SchoolSoft doesn't send a structured "this dish is vegetarian" flag --
    /// a day's raw text just sometimes has a second line for a vegetarian
    /// alternative (see the parsing note on `LunchWeekDTO` in
    /// SchoolSoftScheduleService.swift). This splits `dishes` on a simple
    /// keyword match instead of relying on a field that doesn't exist.
    private static let vegetarianKeywords = ["vegetarisk", "vegetarian", "veg:"]

    private var vegetarianLines: [String] {
        dishes.filter { dish in Self.vegetarianKeywords.contains { dish.localizedCaseInsensitiveContains($0) } }
    }

    private var nonVegetarianLines: [String] {
        dishes.filter { dish in !Self.vegetarianKeywords.contains { dish.localizedCaseInsensitiveContains($0) } }
    }

    /// The dishes to show for the given menu mode. When the day doesn't
    /// distinguish a vegetarian alternative at all (no line matched the
    /// keywords), both modes fall back to showing everything that's there
    /// rather than going blank.
    public func dishes(for mode: LunchMenuMode) -> [String] {
        switch mode {
        case .vegetarian:
            return vegetarianLines.isEmpty ? dishes : vegetarianLines
        case .normal:
            return nonVegetarianLines.isEmpty ? dishes : nonVegetarianLines
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
