import WidgetKit
import SwiftUI

public struct ScheduleEntry: TimelineEntry {
    public let date: Date
    public let schedule: Schedule?

    public init(date: Date, schedule: Schedule?) {
        self.date = date
        self.schedule = schedule
    }
}

public struct ScheduleProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: .now, schedule: .sample)
    }

    public func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        let schedule = ScheduleCache.load() ?? .sample
        completion(ScheduleEntry(date: .now, schedule: schedule))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let currentDate = Date()
        let schedule = ScheduleCache.load() ?? .sample
        let todayLessons = schedule.lessons(for: currentDate)

        var entries: [ScheduleEntry] = []
        // Base entry for current time
        entries.append(ScheduleEntry(date: currentDate, schedule: schedule))

        // Create entries at the start and end of upcoming lessons so the widget updates in real-time
        for lesson in todayLessons {
            if lesson.start > currentDate {
                entries.append(ScheduleEntry(date: lesson.start, schedule: schedule))
            }
            if lesson.end > currentDate {
                entries.append(ScheduleEntry(date: lesson.end, schedule: schedule))
            }
        }

        // Default refresh after 30 minutes or at end of last lesson
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(1800)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

public struct ScheduleWidget: Widget {
    public let kind = "ScheduleWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("School Schedule")
        .description("Keep track of current and upcoming lessons. Switch the large widget between a week view and today-only in Settings.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct ScheduleWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ScheduleEntry

    private var todayLessons: [Lesson] {
        entry.schedule?.lessons(for: entry.date) ?? []
    }

    var body: some View {
        switch family {
        case .systemLarge:
            switch ScheduleCache.largeWidgetMode {
            case .week:
                // Week-at-a-glance stays useful even on a day with nothing
                // scheduled, so it doesn't gate on todayLessons being empty.
                WeekScheduleView(entryDate: entry.date, schedule: entry.schedule)
            case .today:
                if todayLessons.isEmpty {
                    emptyTodayView
                } else {
                    TodayLargeScheduleView(entryDate: entry.date, lessons: todayLessons)
                }
            }
        case .systemMedium:
            if todayLessons.isEmpty {
                emptyTodayView
            } else {
                MediumScheduleView(entryDate: entry.date, lessons: todayLessons)
            }
        default:
            if todayLessons.isEmpty {
                emptyTodayView
            } else {
                SmallScheduleView(entryDate: entry.date, lessons: todayLessons)
            }
        }
    }

    private var emptyTodayView: some View {
        ContentUnavailableView(
            "No Lessons Today",
            systemImage: "calendar.badge.clock",
            description: Text("Enjoy your free time!")
        )
    }
}

// MARK: - Small Widget View
private struct SmallScheduleView: View {
    let entryDate: Date
    let lessons: [Lesson]

    private var activeLesson: Lesson? {
        lessons.first { $0.isActive(at: entryDate) }
    }

    private var nextLesson: Lesson? {
        lessons.first { $0.start > entryDate }
    }

    private var remainingCount: Int {
        lessons.filter { $0.end > entryDate }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entryDate.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if remainingCount > 0 {
                    Text("\(remainingCount) left")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }

            if let active = activeLesson {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("NOW")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }

                    Text(active.subject)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if let room = active.room {
                        Text("Room \(room)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text("Ends \(active.end, format: .dateTime.hour().minute())")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if let next = nextLesson {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT UP")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)

                    Text(next.subject)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if let room = next.room {
                        Text("Room \(room)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text("Starts \(next.start, format: .dateTime.hour().minute())")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .center, spacing: 6) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Day Complete")
                        .font(.subheadline.weight(.medium))
                    Text("All lessons done")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium Widget View
private struct MediumScheduleView: View {
    let entryDate: Date
    let lessons: [Lesson]

    private var activeLesson: Lesson? {
        lessons.first { $0.isActive(at: entryDate) }
    }

    private var upcomingLessons: [Lesson] {
        lessons.filter { $0.end > entryDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entryDate.formatted(date: .complete, time: .omitted).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(lessons.count) Lessons")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 14) {
                // Left column: Current focus
                VStack(alignment: .leading, spacing: 4) {
                    if let active = activeLesson {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("HAPPENING NOW")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        }
                        Text(active.subject)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text(active.formattedTimeRange)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let room = active.room {
                            Text("Room \(room)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let next = lessons.first(where: { $0.start > entryDate }) {
                        Text("UP NEXT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                        Text(next.subject)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text(next.formattedTimeRange)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let room = next.room {
                            Text("Room \(room)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Spacer()
                        Label("All Done", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("No more lessons scheduled today.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Right column: Upcoming list
                VStack(alignment: .leading, spacing: 6) {
                    let upcoming = upcomingLessons.prefix(3)
                    if upcoming.isEmpty {
                        Text("No upcoming classes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcoming) { lesson in
                            HStack(alignment: .center, spacing: 6) {
                                Text(lesson.start, format: .dateTime.hour().minute())
                                    .font(.caption.monospacedDigit().weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .leading)

                                Text(lesson.subject)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let room = lesson.room {
                                    Text(room)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large Widget View: "Today Only" classic agenda list (shows end times)
private struct TodayLargeScheduleView: View {
    let entryDate: Date
    let lessons: [Lesson]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entryDate.formatted(date: .complete, time: .omitted).uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Today's Schedule")
                        .font(.headline)
                }
                Spacer()
                Text("\(lessons.count) classes")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 6) {
                ForEach(lessons.prefix(6)) { lesson in
                    let isCurrent = lesson.isActive(at: entryDate)
                    let isPast = lesson.isPast(at: entryDate)

                    HStack(spacing: 8) {
                        Text(lesson.formattedTimeRange)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(isPast ? .tertiary : (isCurrent ? .primary : .secondary))
                            .frame(width: 86, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(lesson.subject)
                                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isPast ? .secondary : .primary)
                                    .strikethrough(isPast, color: .secondary.opacity(0.5))

                                if isCurrent {
                                    Text("NOW")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.15), in: Capsule())
                                }
                            }

                            if let teacher = lesson.teacher {
                                Text(teacher)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        if let room = lesson.room {
                            Text(room)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    isCurrent ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large Widget View: "This Week" whole-week view, Monday–Friday
private struct WeekScheduleView: View {
    let entryDate: Date
    let schedule: Schedule?

    private var weekdays: [WeekdaySchedule] {
        schedule?.weekdayLessons(for: entryDate) ?? []
    }

    private var hasAnyLessons: Bool {
        weekdays.contains { !$0.lessons.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(weekRangeLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("This Week")
                        .font(.headline)
                }
                Spacer()
            }

            Divider()

            if hasAnyLessons {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(weekdays.enumerated()), id: \.element.id) { index, day in
                        DayColumn(date: day.date, lessons: day.lessons, entryDate: entryDate)
                        if index < weekdays.count - 1 {
                            Divider()
                        }
                    }
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    ContentUnavailableView(
                        "No Lessons This Week",
                        systemImage: "calendar.badge.clock",
                        description: Text("Enjoy your time off!")
                    )
                    Spacer()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var weekRangeLabel: String {
        guard let first = weekdays.first?.date, let last = weekdays.last?.date else {
            return entryDate.formatted(date: .complete, time: .omitted)
        }
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(first.formatted(format)) – \(last.formatted(format))"
    }
}

/// One weekday's column of lesson "blocks" inside the week widget.
/// The currently active lesson (today only) is highlighted white so it
/// pops against the widget's translucent background.
private struct DayColumn: View {
    let date: Date
    let lessons: [Lesson]
    let entryDate: Date

    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: entryDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)

            if lessons.isEmpty {
                Text("–")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 3) {
                    ForEach(lessons) { lesson in
                        LessonBlock(lesson: lesson, isToday: isToday, entryDate: entryDate)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct LessonBlock: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let lesson: Lesson
    let isToday: Bool
    let entryDate: Date

    private var isActive: Bool { isToday && lesson.isActive(at: entryDate) }
    private var isPast: Bool { isToday && lesson.isPast(at: entryDate) }

    // Same full-color-only treatment as the Lunch widget: a filled white box
    // only makes sense when the widget is actually rendering full color. In
    // any other rendering mode (e.g. macOS desktop widgets while another
    // window has focus), an opaque fill and opaque black text both reduce to
    // the same silhouette and the text disappears -- so fall back to an
    // outline instead of a fill.
    private var activeForeground: AnyShapeStyle {
        renderingMode == .fullColor ? AnyShapeStyle(Color.black) : AnyShapeStyle(.primary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(lesson.start, format: .dateTime.hour().minute())
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(isActive ? activeForeground : AnyShapeStyle(.secondary))
            Text(lesson.subject)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? activeForeground : AnyShapeStyle(isPast ? .secondary : .primary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if renderingMode == .fullColor {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.white : Color.secondary.opacity(isPast ? 0.05 : 0.12))
            } else if isActive {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
                    .widgetAccentable()
            }
        }
        .opacity(isPast ? 0.6 : 1)
    }
}

// MARK: - Widget Bundle Entry Point
@main
struct SchoolSoftWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        LunchWidget()
    }
}

// MARK: - Previews
#Preview("Small Widget", as: .systemSmall) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(date: .now, schedule: .sample)
}

#Preview("Medium Widget", as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(date: .now, schedule: .sample)
}

#Preview("Large Widget", as: .systemLarge) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(date: .now, schedule: .sample)
}
