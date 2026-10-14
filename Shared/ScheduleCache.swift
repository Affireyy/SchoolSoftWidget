import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Which layout the large widget uses. Stored in the shared cache file so
/// both the app (Settings) and the widget extension (a separate process/
/// sandbox) see the same value.
public enum LargeWidgetMode: String, CaseIterable, Identifiable, Sendable {
    case week = "This Week"
    case today = "Today Only"

    public var id: String { rawValue }
}

/// Everything a process needs to read, as one Codable snapshot. On macOS the
/// app and widget share a file; on iOS each process keeps its own cache and
/// the widget fetches directly using its configuration.
private struct CachedState: Codable {
    var scheduleData: Data?
    var lunchMenuData: Data?
    var lastSync: Date?
    var lastError: String?
    var largeWidgetMode: String?
    var lunchMenuMode: String?
}

public enum ScheduleCache {
    // macOS shares the cache with its widget via a fixed home-directory
    // file and a read-only sandbox exception. iOS deliberately does not use
    // an App Group: free developer accounts cannot sign that entitlement,
    // and the iOS widget obtains data directly from its configured login.
    private static let cacheDirectoryRelativePath = "Library/Application Support/SchoolSoftWidget"
    private static let cacheFileName = "cache.json"

    /// Resolves the user's real home directory. `FileManager`'s standard
    /// home-directory APIs return the sandbox container's fake home when
    /// called from a sandboxed process (like the widget extension), so this
    /// goes through libc instead, which always reports the true home
    /// regardless of sandboxing -- matching what the entitlement above is
    /// actually granted relative to.
    #if os(macOS)
    private static var realHomeDirectory: URL {
        if let pwd = getpwuid(getuid()), let dir = pwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
    #endif

    private static var cacheDirectory: URL {
        #if os(iOS)
        // Each iOS target gets its own sandbox Application Support directory.
        // The widget's direct fetch does not depend on the app's cache.
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolSoftWidget", isDirectory: true)
        #else
        return realHomeDirectory.appendingPathComponent(cacheDirectoryRelativePath, isDirectory: true)
        #endif
    }

    private static var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(cacheFileName)
    }

    /// Shown in Settings for diagnostics.
    public static var sharedCacheDirectoryPath: String {
        cacheDirectory.path
    }

    private static func readState() -> CachedState {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let state = try? JSONDecoder().decode(CachedState.self, from: data) else {
            return CachedState()
        }
        return state
    }

    /// Only the app calls this -- the widget's sandbox entitlement is
    /// read-only, so a write from the widget process would fail anyway.
    private static func writeState(_ mutate: (inout CachedState) -> Void) {
        var state = readState()
        mutate(&state)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheFileURL, options: .atomic)
    }

    public static func save(_ schedule: Schedule) {
        var mutableSchedule = schedule
        if mutableSchedule.lastUpdated == nil {
            mutableSchedule.lastUpdated = .now
        }

        if let data = try? JSONEncoder().encode(mutableSchedule) {
            writeState { state in
                state.scheduleData = data
                state.lastSync = .now
                state.lastError = nil
            }
        }
        reloadWidgets()
    }

    public static func load() -> Schedule? {
        guard let data = readState().scheduleData else { return nil }
        return try? JSONDecoder().decode(Schedule.self, from: data)
    }

    public static func save(_ lunchMenu: LunchMenu) {
        var mutableMenu = lunchMenu
        if mutableMenu.lastUpdated == nil {
            mutableMenu.lastUpdated = .now
        }

        if let data = try? JSONEncoder().encode(mutableMenu) {
            writeState { state in state.lunchMenuData = data }
        }
        reloadWidgets()
    }

    public static func loadLunchMenu() -> LunchMenu? {
        guard let data = readState().lunchMenuData else { return nil }
        return try? JSONDecoder().decode(LunchMenu.self, from: data)
    }

    /// Which layout the large School Schedule widget should use. Defaults
    /// to the Monday–Friday week view; switch to `.today` for the classic
    /// single-day agenda list (with lesson end times).
    public static var largeWidgetMode: LargeWidgetMode {
        get {
            if let raw = readState().largeWidgetMode, let mode = LargeWidgetMode(rawValue: raw) {
                return mode
            }
            return .week
        }
        set {
            writeState { state in state.largeWidgetMode = newValue.rawValue }
            reloadWidgets()
        }
    }

    /// Which alternative (normal or vegetarian) to show when a day's lunch
    /// lists more than one dish. Defaults to normal.
    public static var lunchMenuMode: LunchMenuMode {
        get {
            if let raw = readState().lunchMenuMode, let mode = LunchMenuMode(rawValue: raw) {
                return mode
            }
            return .normal
        }
        set {
            writeState { state in state.lunchMenuMode = newValue.rawValue }
            reloadWidgets()
        }
    }

    /// Used by the iOS widget extension, which fetches its own data (no App
    /// Group on free signing). Unlike `save`, this never asks WidgetKit to
    /// reload, since it runs inside a timeline request.
    public static func storeFromWidget(schedule: Schedule?, lunchMenu: LunchMenu?,
                                       largeMode: LargeWidgetMode? = nil, lunchMode: LunchMenuMode? = nil) {
        var schedule = schedule
        schedule?.lastUpdated = .now
        var lunchMenu = lunchMenu
        lunchMenu?.lastUpdated = .now
        let scheduleData = schedule.flatMap { try? JSONEncoder().encode($0) }
        let lunchData = lunchMenu.flatMap { try? JSONEncoder().encode($0) }
        writeState { state in
            if let scheduleData { state.scheduleData = scheduleData; state.lastSync = .now; state.lastError = nil }
            if let lunchData { state.lunchMenuData = lunchData }
            if let largeMode { state.largeWidgetMode = largeMode.rawValue }
            if let lunchMode { state.lunchMenuMode = lunchMode.rawValue }
        }
    }

    public static func recordError(_ message: String) {
        writeState { state in state.lastError = message }
    }

    public static var lastSyncDate: Date? {
        readState().lastSync
    }

    public static var lastError: String? {
        readState().lastError
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: cacheFileURL)
        reloadWidgets()
    }

    public static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
