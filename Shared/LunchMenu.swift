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

    /// SchoolSoft doesn't send a structured "this dish is vegetarian" flag.
    /// The real API text comes back as a flat list of lines where a label
    /// (e.g. "Vegetarisk" or "Lunch") sits on its own line immediately
    /// before the dish it describes -- not inline with the dish text, e.g.:
    ///   ["Vegetarisk", "Majsbiff med kokt potatis...", "Lunch", "Nötfärsbiff..."]
    /// Some other source (or the bundled sample data) instead writes the
    /// label inline on the same line as the dish, e.g. "Vegetarian: Bean
    /// taco buffet". Both shapes are handled below. A line matching neither
    /// pattern (e.g. a day with only a single, unlabeled dish) is treated as
    /// common to both modes rather than dropped.
    private static let standaloneVegetarianLabels: Set<String> = ["vegetarisk", "vegetariskt", "veg"]
    private static let standaloneNormalLabels: Set<String> = ["lunch", "kött", "dagens lunch"]
    private static let inlineVegetarianKeywords = ["vegetarisk", "vegetarian", "veg:"]
    private static let ignoredMarkers: Set<String> = ["idag", "today"]

    private struct Categorized {
        var normal: [String] = []
        var vegetarian: [String] = []
        var unlabeled: [String] = []
    }

    private var categorizedDishes: Categorized {
        var result = Categorized()
        var index = 0
        while index < dishes.count {
            let line = dishes[index]
            let key = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if Self.ignoredMarkers.contains(key) {
                index += 1
                continue
            }

            if Self.standaloneVegetarianLabels.contains(key), index + 1 < dishes.count {
                result.vegetarian.append(dishes[index + 1])
                index += 2
                continue
            }

            if Self.standaloneNormalLabels.contains(key), index + 1 < dishes.count {
                result.normal.append(dishes[index + 1])
                index += 2
                continue
            }

            if Self.inlineVegetarianKeywords.contains(where: { key.contains($0) }) {
                result.vegetarian.append(line)
                index += 1
                continue
            }

            result.unlabeled.append(line)
            index += 1
        }
        return result
    }

    /// The dishes to show for the given menu mode.
    ///
    /// An unlabeled line is treated as the implicit "normal" dish (that's
    /// how the bundled sample data marks only the vegetarian alternative
    /// and leaves the regular dish bare) -- *unless* the day had no labels
    /// at all, meaning there's nothing to distinguish, in which case both
    /// modes just show everything that's there rather than going blank.
    public func dishes(for mode: LunchMenuMode) -> [String] {
        let categorized = categorizedDishes
        guard !(categorized.normal.isEmpty && categorized.vegetarian.isEmpty) else {
            return dishes
        }
        switch mode {
        case .vegetarian:
            return categorized.vegetarian.isEmpty ? categorized.unlabeled : categorized.vegetarian
        case .normal:
            let result = categorized.normal + categorized.unlabeled
            return result.isEmpty ? dishes : result
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
