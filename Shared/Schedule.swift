import Foundation

public struct Schedule: Codable, Sendable, Equatable {
    public var lessons: [Lesson]
    public var lastUpdated: Date?

    public init(lessons: [Lesson], lastUpdated: Date? = .now) {
        self.lessons = lessons.sorted { $0.start < $1.start }
        self.lastUpdated = lastUpdated
    }

    /// Returns lessons for a specific calendar day.
    public func lessons(for date: Date = .now, calendar: Calendar = .current) -> [Lesson] {
        lessons.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    /// Lesson currently in progress at `date`.
    public func activeLesson(at date: Date = .now) -> Lesson? {
        lessons.first { $0.isActive(at: date) }
    }

    /// Next lesson starting after `date` on the same day.
    public func nextLesson(at date: Date = .now, calendar: Calendar = .current) -> Lesson? {
        lessons(for: date, calendar: calendar).first { $0.start > date }
    }

    /// All lessons yet to start today after `date`.
    public func remainingLessons(at date: Date = .now, calendar: Calendar = .current) -> [Lesson] {
        lessons(for: date, calendar: calendar).filter { $0.end > date }
    }

    /// Returns each weekday (Monday–Friday) of the week containing `date`,
    /// paired with that day's lessons. Saturday and Sunday are intentionally
    /// excluded, matching the school week.
    public func weekdayLessons(for date: Date = .now, calendar: Calendar = .current) -> [WeekdaySchedule] {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2 // Monday

        guard let weekInterval = weekCalendar.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }

        return (0..<5).compactMap { offset -> WeekdaySchedule? in
            guard let day = weekCalendar.date(byAdding: .day, value: offset, to: weekInterval.start) else {
                return nil
            }
            return WeekdaySchedule(date: day, lessons: lessons(for: day, calendar: weekCalendar))
        }
    }

    /// Generates a realistic sample schedule relative to today.
    public static var sample: Schedule {
        let calendar = Calendar.current
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let today = calendar.startOfDay(for: .now)
        let weekStart = weekCalendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        func lessonTime(dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = weekCalendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let todayOffset = weekCalendar.dateComponents([.day], from: weekStart, to: today).day.map { max(0, min(4, $0)) } ?? 0

        var sampleLessons = [
            Lesson(id: "sample-1", subject: "Mathematics 4", room: "A204", teacher: "E. Lindgren", start: lessonTime(dayOffset: todayOffset, 8, 30), end: lessonTime(dayOffset: todayOffset, 9, 45)),
            Lesson(id: "sample-2", subject: "Swedish 3", room: "B112", teacher: "K. Ström", start: lessonTime(dayOffset: todayOffset, 10, 00), end: lessonTime(dayOffset: todayOffset, 11, 15)),
            Lesson(id: "sample-3", subject: "Physics 2", room: "Lab 3", teacher: "M. Nilsson", start: lessonTime(dayOffset: todayOffset, 12, 00), end: lessonTime(dayOffset: todayOffset, 13, 20)),
            Lesson(id: "sample-4", subject: "Programming 2", room: "C308", teacher: "D. Bergman", start: lessonTime(dayOffset: todayOffset, 13, 35), end: lessonTime(dayOffset: todayOffset, 14, 50)),
            Lesson(id: "sample-5", subject: "English 7", room: "B104", teacher: "S. Johnson", start: lessonTime(dayOffset: todayOffset, 15, 05), end: lessonTime(dayOffset: todayOffset, 16, 15))
        ]

        // Fill out the rest of the week too, so a systemLarge widget preview has something in every column.
        let otherDaySubjects: [(String, String, String)] = [
            ("History 2", "C110", "A. Berg"),
            ("Chemistry 1", "Lab 1", "P. Ek"),
            ("Art", "D201", "L. Vik"),
            ("PE", "Gym", "R. Holm")
        ]
        for offset in 0..<5 where offset != todayOffset {
            let (subject, room, teacher) = otherDaySubjects[offset % otherDaySubjects.count]
            sampleLessons.append(
                Lesson(id: "sample-day\(offset)-1", subject: subject, room: room, teacher: teacher, start: lessonTime(dayOffset: offset, 9, 0), end: lessonTime(dayOffset: offset, 10, 15))
            )
            sampleLessons.append(
                Lesson(id: "sample-day\(offset)-2", subject: "Mathematics 4", room: "A204", teacher: "E. Lindgren", start: lessonTime(dayOffset: offset, 11, 0), end: lessonTime(dayOffset: offset, 12, 15))
            )
        }

        return Schedule(lessons: sampleLessons, lastUpdated: .now)
    }
}

/// A single weekday paired with its lessons, used to render week-at-a-glance views.
public struct WeekdaySchedule: Identifiable, Sendable, Equatable {
    public var date: Date
    public var lessons: [Lesson]

    public var id: Date { date }

    public init(date: Date, lessons: [Lesson]) {
        self.date = date
        self.lessons = lessons
    }
}

public struct Lesson: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var subject: String
    public var room: String?
    public var teacher: String?
    public var start: Date
    public var end: Date

    public init(
        id: String = UUID().uuidString,
        subject: String,
        room: String? = nil,
        teacher: String? = nil,
        start: Date,
        end: Date
    ) {
        self.id = id
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.start = start
        self.end = end
    }

    public var durationMinutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }

    public func isActive(at date: Date = .now) -> Bool {
        date >= start && date < end
    }

    public func isUpcoming(at date: Date = .now) -> Bool {
        date < start
    }

    public func isPast(at date: Date = .now) -> Bool {
        date >= end
    }

    public var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}
