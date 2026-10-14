#if os(iOS)
import SwiftUI

/// iOS root: the schedule and lunch menu synced by the Account tab, plus
/// the account/settings screen itself.
struct RootTabView: View {
    @State private var selection = ScheduleCache.load() == nil ? Tab.setup : Tab.schedule

    private enum Tab { case schedule, lunch, account, setup }

    var body: some View {
        TabView(selection: $selection) {
            ScheduleTabView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(Tab.schedule)
            LunchTabView()
                .tabItem { Label("Lunch", systemImage: "fork.knife") }
                .tag(Tab.lunch)
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(Tab.account)
            SetupGuideView()
                .tabItem { Label("Setup", systemImage: "questionmark.circle") }
                .tag(Tab.setup)
        }
    }
}

private struct SetupGuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("1. Sync the app") {
                    step("Open the Account tab.")
                    step("Enter your School URL (for example https://sms13.schoolsoft.se/yourschool), username and password.")
                    step("Tap Connect & Sync. Your schedule and lunch menu then appear in the Schedule and Lunch tabs.")
                }
                Section("2. Add the widgets") {
                    step("Touch and hold an empty spot on the Home Screen, then tap + (top left).")
                    step("Search for \"SchoolSoft\" and add School Schedule and/or Lunch Menu in the size you like.")
                }
                Section("3. Set up each widget") {
                    step("Touch and hold the widget, then tap Edit Widget.")
                    step("Enter the same School URL, username and password. Each widget needs its own login.")
                    step("On the large School Schedule widget you can also choose This Week or Today Only. On Lunch Menu you can choose Normal or Vegetarian.")
                }
                Section("Good to know") {
                    step("Until a widget has a login it shows setup instructions instead of data.")
                    step("The password in a widget is stored in the widget's configuration, not the Keychain.")
                    step("Apps installed with a free Apple ID expire after 7 days and must be reinstalled.")
                }
            }
            .navigationTitle("Setup")
        }
    }

    private func step(_ text: String) -> some View {
        Text(text).font(.callout)
    }
}

private struct ScheduleTabView: View {
    @State private var schedule: Schedule?
    @State private var didScrollToCurrentLesson = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Group {
                    if let schedule, !schedule.lessons.isEmpty {
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            List {
                                ForEach(schedule.weekdayLessons(for: timeline.date)) { day in
                                    Section {
                                        if day.lessons.isEmpty {
                                            Text("No lessons").foregroundStyle(.secondary)
                                        }
                                        ForEach(Array(day.lessons.enumerated()), id: \.element.id) { index, lesson in
                                            VStack(alignment: .leading, spacing: 0) {
                                                LessonRow(
                                                    lesson: lesson,
                                                    isCurrent: lesson.isActive(at: timeline.date)
                                                )
                                                .id(lesson.id)

                                                if index + 1 < day.lessons.count {
                                                    let minutes = Int(day.lessons[index + 1].start.timeIntervalSince(lesson.end) / 60)
                                                    if minutes > 0 {
                                                        HStack(spacing: 5) {
                                                            Image(systemName: "cup.and.saucer")
                                                            Text("\(breakDurationText(minutes)) break")
                                                        }
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .padding(.top, 5)
                                                        .padding(.leading, 4)
                                                    }
                                                }
                                            }
                                        }
                                    } header: {
                                        Text(day.date.formatted(.dateTime.weekday(.wide).day().month()))
                                    }
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "No Schedule",
                            systemImage: "calendar",
                            description: Text("Open the Account tab and tap Connect & Sync to load your schedule.")
                        )
                    }
                }
                .navigationTitle("Schedule")
                .onAppear {
                    schedule = ScheduleCache.load()
                    scrollToCurrentLesson(using: scrollProxy)
                }
                .onChange(of: schedule) { _, _ in
                    scrollToCurrentLesson(using: scrollProxy)
                }
            }
        }
    }

    private func breakDurationText(_ minutes: Int) -> String {
        let minutes = max(1, minutes)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        switch (hours, remainingMinutes) {
        case (0, _):
            return "\(minutes) min"
        case (_, 0):
            return "\(hours) hr"
        default:
            return "\(hours) hr \(remainingMinutes) min"
        }
    }

    private func scrollToCurrentLesson(using proxy: ScrollViewProxy) {
        guard !didScrollToCurrentLesson,
              let schedule,
              let lesson = schedule.activeLesson() ?? schedule.nextLesson() else {
            return
        }
        didScrollToCurrentLesson = true
        Task { @MainActor in
            await Task.yield()
            withAnimation {
                proxy.scrollTo(lesson.id, anchor: .center)
            }
        }
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(lesson.subject).font(.headline)
                Spacer()
                if isCurrent {
                    Label("Now", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text(lesson.formattedTimeRange)
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
            }
            let details = [lesson.room, lesson.teacher].compactMap { $0 }.filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(lesson.isPast() ? 0.6 : 1)
        .padding(.vertical, isCurrent ? 4 : 0)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.14) : Color.clear)
    }
}

private struct LunchTabView: View {
    @State private var menu: LunchMenu?
    @State private var mode: LunchMenuMode = ScheduleCache.lunchMenuMode

    var body: some View {
        NavigationStack {
            Group {
                if let menu, !menu.days.isEmpty {
                    List {
                        Picker("Show", selection: $mode) {
                            ForEach(LunchMenuMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _, newValue in ScheduleCache.lunchMenuMode = newValue }

                        ForEach(menu.days) { day in
                            Section(day.date.formatted(.dateTime.weekday(.wide).day().month())) {
                                let dishes = day.dishes(for: mode)
                                if dishes.isEmpty {
                                    Text("No lunch listed").foregroundStyle(.secondary)
                                }
                                ForEach(dishes, id: \.self) { Text($0) }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Lunch Menu",
                        systemImage: "fork.knife",
                        description: Text("Open the Account tab and tap Connect & Sync to load the menu.")
                    )
                }
            }
            .navigationTitle("Lunch")
        }
        .onAppear { menu = ScheduleCache.loadLunchMenu() }
    }
}
#endif
