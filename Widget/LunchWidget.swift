import WidgetKit
import SwiftUI

public struct LunchEntry: TimelineEntry {
    public let date: Date
    public let lunchMenu: LunchMenu?

    public init(date: Date, lunchMenu: LunchMenu?) {
        self.date = date
        self.lunchMenu = lunchMenu
    }
}

public struct LunchProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> LunchEntry {
        LunchEntry(date: .now, lunchMenu: .sample)
    }

    public func getSnapshot(in context: Context, completion: @escaping (LunchEntry) -> Void) {
        let menu = ScheduleCache.loadLunchMenu() ?? .sample
        completion(LunchEntry(date: .now, lunchMenu: menu))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<LunchEntry>) -> Void) {
        let currentDate = Date()
        let menu = ScheduleCache.loadLunchMenu() ?? .sample
        let entry = LunchEntry(date: currentDate, lunchMenu: menu)

        // The menu doesn't change intraday; refresh shortly after midnight so
        // "today's" column advances, with a same-day fallback as a safety net.
        let nextRefresh = Calendar.current.nextDate(
            after: currentDate,
            matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? currentDate.addingTimeInterval(6 * 3600)

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

public struct LunchWidget: Widget {
    public let kind = "LunchWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LunchProvider()) { entry in
            LunchWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Lunch Menu")
        .description("See what's for school lunch today — the large widget shows the whole week (Mon–Fri).")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

private struct LunchWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: LunchEntry

    private var todayMenu: LunchDay? {
        entry.lunchMenu?.menu(for: entry.date)
    }

    var body: some View {
        if entry.lunchMenu?.days.isEmpty ?? true {
            ContentUnavailableView(
                "No Lunch Menu",
                systemImage: "fork.knife",
                description: Text("Sync your account to load this week's menu.")
            )
        } else {
            switch family {
            case .systemLarge:
                LunchWeekRowsView(entryDate: entry.date, lunchMenu: entry.lunchMenu)
            case .systemMedium:
                MediumLunchWeekView(entryDate: entry.date, lunchMenu: entry.lunchMenu)
            default:
                SmallLunchView(entryDate: entry.date, today: todayMenu)
            }
        }
    }
}

// MARK: - Small Widget View
private struct SmallLunchView: View {
    let entryDate: Date
    let today: LunchDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                    .font(.caption)
                Text(entryDate.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.secondary)

            if let today, !today.dishes.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(today.dishes.prefix(2), id: \.self) { dish in
                        Text(dish)
                            .font(.body)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                Spacer()
                Text("No menu for today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large Widget View: whole week, one horizontal row per weekday.
// Each row is the day label and that day's dishes laid out side-by-side,
// with the five rows stacked top-to-bottom.
private struct LunchWeekRowsView: View {
    let entryDate: Date
    let lunchMenu: LunchMenu?

    private var weekdays: [Date] {
        var weekCalendar = Calendar.current
        weekCalendar.firstWeekday = 2
        guard let interval = weekCalendar.dateInterval(of: .weekOfYear, for: entryDate) else { return [] }
        return (0..<5).compactMap { weekCalendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lunch This Week")
                    .font(.headline)
                Spacer()
                Image(systemName: "fork.knife")
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 6) {
                ForEach(weekdays, id: \.self) { date in
                    LunchDayRow(
                        date: date,
                        menu: lunchMenu?.menu(for: date),
                        isToday: Calendar.current.isDate(date, inSameDayAs: entryDate)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One weekday's row: the day label and that day's dishes side-by-side,
/// highlighted white when it's today.
private struct LunchDayRow: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let date: Date
    let menu: LunchDay?
    let isToday: Bool

    // In full-color mode, today's row gets a filled white box with black
    // text. In any other rendering mode (e.g. macOS desktop widgets while
    // another window has focus) a fully-opaque fill and fully-opaque text
    // both collapse to the same silhouette, hiding the text -- so instead
    // draw just an outline and let the text stay in the normal hierarchy.
    private var todayForeground: AnyShapeStyle {
        renderingMode == .fullColor ? AnyShapeStyle(Color.black) : AnyShapeStyle(.primary)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isToday ? todayForeground : AnyShapeStyle(.secondary))
                .frame(width: 38, alignment: .leading)

            if let dishes = menu?.dishes, !dishes.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(dishes, id: \.self) { dish in
                        Text(dish)
                            .font(.system(size: 12))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(isToday ? todayForeground : AnyShapeStyle(Color.primary))
                    }
                }
                Spacer(minLength: 0)
            } else {
                Text("–")
                    .font(.caption2)
                    .foregroundStyle(isToday ? todayForeground : AnyShapeStyle(.tertiary))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if renderingMode == .fullColor {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isToday ? Color.white : Color.secondary.opacity(0.06))
            } else if isToday {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.2)
                    .widgetAccentable()
            }
        }
    }
}

// MARK: - Medium Widget View: compact Mon–Fri columns.
private struct MediumLunchWeekView: View {
    let entryDate: Date
    let lunchMenu: LunchMenu?

    private var weekdays: [Date] {
        var weekCalendar = Calendar.current
        weekCalendar.firstWeekday = 2
        guard let interval = weekCalendar.dateInterval(of: .weekOfYear, for: entryDate) else { return [] }
        return (0..<5).compactMap { weekCalendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Lunch This Week")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "fork.knife")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 6) {
                ForEach(weekdays, id: \.self) { date in
                    MediumLunchDayColumn(
                        date: date,
                        menu: lunchMenu?.menu(for: date),
                        isToday: Calendar.current.isDate(date, inSameDayAs: entryDate)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumLunchDayColumn: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let date: Date
    let menu: LunchDay?
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))

            // The box grows to fill the rest of the column's height (instead
            // of hugging the dish text with a trailing Spacer), so today's
            // highlight reaches all the way to the bottom of the widget.
            // minimumScaleFactor is kept aggressive so a long dish name
            // shrinks to fit rather than clipping against the widget's edge.
            Group {
                if let dishes = menu?.dishes, !dishes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(dishes.prefix(1), id: \.self) { dish in
                            Text(dish)
                                .font(.system(size: 14))
                                .lineLimit(3)
                                .minimumScaleFactor(0.55)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("–")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if renderingMode == .fullColor {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isToday ? Color.white : Color.secondary.opacity(0.08))
                } else if isToday {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.2)
                        .widgetAccentable()
                }
            }
            .foregroundStyle(
                (renderingMode == .fullColor && isToday) ? AnyShapeStyle(Color.black) : AnyShapeStyle(Color.primary)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}


// MARK: - Previews
#Preview("Small Widget", as: .systemSmall) {
    LunchWidget()
} timeline: {
    LunchEntry(date: .now, lunchMenu: .sample)
}

#Preview("Medium Widget", as: .systemMedium) {
    LunchWidget()
} timeline: {
    LunchEntry(date: .now, lunchMenu: .sample)
}

#Preview("Large Widget", as: .systemLarge) {
    LunchWidget()
} timeline: {
    LunchEntry(date: .now, lunchMenu: .sample)
}
