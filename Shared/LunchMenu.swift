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
}
