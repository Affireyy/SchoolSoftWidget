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

/// Everything the widget needs to read, as one Codable snapshot. The app
/// (unsandboxed) writes this as a single JSON file; the widget (sandboxed)
/// reads it via a home-relative-path sandbox exception -- see the widget
/// target's entitlements and the note on `cacheDirectoryRelativePath` below.
private struct CachedState: Codable {
    var scheduleData: Data?
    var lunchMenuData: Data?
    var lastSync: Date?
    var lastError: String?
    var largeWidgetMode: String?
}

public enum ScheduleCache {
    // App Groups would normally be the standard way to share data like this
    // between an app and its widget extension, but that capability requires
    // a real, Apple-issued Team ID -- i.e. a paid Apple Developer Program
    // membership -- to actually function for anyone other than the machine
    // it was created on (see README). Since this project ships ad-hoc
    // signed with no team so it can be built and distributed for free, it
    // shares data with a plain file instead: the (unsandboxed) app writes
    // it to a fixed, well-known path in the user's real home directory, and
    // the widget is granted read-only access to exactly that one path via a
    // `com.apple.security.temporary-exception.files.home-relative-path.read-only`
    // entitlement. That's a sandbox rule macOS enforces locally, so unlike
    // App Groups it works regardless of code-signing team.
    private static let cacheDirectoryRelativePath = "Library/Application Support/SchoolSoftWidget"
    private static let cacheFileName = "cache.json"

    /// Resolves the user's real home directory. `FileManager`'s standard
    /// home-directory APIs return the sandbox container's fake home when
    /// called from a sandboxed process (like the widget extension), so this
    /// goes through libc instead, which always reports the true home
    /// regardless of sandboxing -- matching what the entitlement above is
    /// actually granted relative to.
    private static var realHomeDirectory: URL {
        if let pwd = getpwuid(getuid()), let dir = pwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static var cacheDirectory: URL {
        realHomeDirectory.appendingPathComponent(cacheDirectoryRelativePath, isDirectory: true)
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
