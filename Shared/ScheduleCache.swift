import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Which layout the large widget uses. Stored in the shared App Group
/// UserDefaults suite so both the app (Settings) and the widget extension
/// (a separate process/sandbox) see the same value.
public enum LargeWidgetMode: String, CaseIterable, Identifiable, Sendable {
    case week = "This Week"
    case today = "Today Only"

    public var id: String { rawValue }
}

public enum ScheduleCache {
    /// App Group identifier matching the entitlements of both the App and Widget targets.
    public static let appGroupIdentifier = "UDWA7LNKRM.com.dessimondi.SchoolSoftWidget"

    private static let scheduleKey = "cachedSchedule"
    private static let lunchMenuKey = "cachedLunchMenu"
    private static let lastSyncKey = "lastScheduleSync"
    private static let lastErrorKey = "lastScheduleError"
    private static let schoolNameKey = "cachedSchoolName"
    private static let largeWidgetModeKey = "largeWidgetMode"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    public static func save(_ schedule: Schedule) {
        var mutableSchedule = schedule
        if mutableSchedule.lastUpdated == nil {
            mutableSchedule.lastUpdated = .now
        }

        if let data = try? JSONEncoder().encode(mutableSchedule) {
            defaults.set(data, forKey: scheduleKey)
            defaults.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
            defaults.removeObject(forKey: lastErrorKey)
        }
        reloadWidgets()
    }

    public static func load() -> Schedule? {
        guard let data = defaults.data(forKey: scheduleKey) else { return nil }
        return try? JSONDecoder().decode(Schedule.self, from: data)
    }

    public static func save(_ lunchMenu: LunchMenu) {
        var mutableMenu = lunchMenu
        if mutableMenu.lastUpdated == nil {
            mutableMenu.lastUpdated = .now
        }

        if let data = try? JSONEncoder().encode(mutableMenu) {
            defaults.set(data, forKey: lunchMenuKey)
        }
        reloadWidgets()
    }

    public static func loadLunchMenu() -> LunchMenu? {
        guard let data = defaults.data(forKey: lunchMenuKey) else { return nil }
        return try? JSONDecoder().decode(LunchMenu.self, from: data)
    }

    /// Which layout the large School Schedule widget should use. Defaults
    /// to the Monday–Friday week view; switch to `.today` for the classic
    /// single-day agenda list (with lesson end times).
    public static var largeWidgetMode: LargeWidgetMode {
        get {
            if let raw = defaults.string(forKey: largeWidgetModeKey), let mode = LargeWidgetMode(rawValue: raw) {
                return mode
            }
            return .week
        }
        set {
            defaults.set(newValue.rawValue, forKey: largeWidgetModeKey)
            reloadWidgets()
        }
    }

    public static func recordError(_ message: String) {
        defaults.set(message, forKey: lastErrorKey)
    }

    public static var lastSyncDate: Date? {
        let timestamp = defaults.double(forKey: lastSyncKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    public static var lastError: String? {
        defaults.string(forKey: lastErrorKey)
    }

    public static func clear() {
        defaults.removeObject(forKey: scheduleKey)
        defaults.removeObject(forKey: lunchMenuKey)
        defaults.removeObject(forKey: lastSyncKey)
        defaults.removeObject(forKey: lastErrorKey)
        reloadWidgets()
    }

    public static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
