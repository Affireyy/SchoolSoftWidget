#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

public enum LargeModeOption: String, AppEnum {
    case week, today

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Large Widget Shows"
    public static var caseDisplayRepresentations: [LargeModeOption: DisplayRepresentation] = [
        .week: "This Week",
        .today: "Today Only"
    ]

    public var mode: LargeWidgetMode { self == .week ? .week : .today }
}

public enum LunchModeOption: String, AppEnum {
    case normal, vegetarian

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Lunch Option"
    public static var caseDisplayRepresentations: [LunchModeOption: DisplayRepresentation] = [
        .normal: "Normal",
        .vegetarian: "Vegetarian"
    ]

    public var mode: LunchMenuMode { self == .normal ? .normal : .vegetarian }
}

/// Shared by both widget intents. Free (non-paid) signing has no App Groups,
/// so the widget can't read what the app synced; each widget is configured
/// directly (long-press → Edit Widget) and fetches its own data. The
/// password is stored in the widget configuration by the system, not in the
/// Keychain.
enum WidgetSync {
    static let setupMessage = "Not set up yet. Long-press this widget, tap Edit Widget, and enter your School URL, Username and Password."

    static func credentials(url: String?, username: String?, password: String?) -> SchoolSoftCredentials? {
        guard let url, let username, let password,
              !url.trimmingCharacters(in: .whitespaces).isEmpty,
              !username.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else { return nil }
        return SchoolSoftCredentials(schoolURL: url, username: username, password: password)
    }
}

public struct ScheduleWidgetIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource = "School Schedule"
    public static var description = IntentDescription("Your SchoolSoft login, used by the widget to sync directly.")

    @Parameter(title: "School URL")
    public var schoolURL: String?

    @Parameter(title: "Username")
    public var username: String?

    @Parameter(title: "Password")
    public var password: String?

    @Parameter(title: "Large Widget Shows", default: .week)
    public var largeMode: LargeModeOption

    public init() {}

    // The week/today option only affects the large widget, so it's only
    // offered when editing a large one.
    public static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemLarge) {
            Summary {
                \.$schoolURL
                \.$username
                \.$password
                \.$largeMode
            }
        } otherwise: {
            Summary {
                \.$schoolURL
                \.$username
                \.$password
            }
        }
    }

    /// Fetches fresh data and stores it for the views. Returns a message to
    /// show instead of the schedule when there is nothing to display.
    func refreshCache() async -> String? {
        guard let creds = WidgetSync.credentials(url: schoolURL, username: username, password: password) else {
            return WidgetSync.setupMessage
        }
        do {
            let schedule = try await SchoolSoftClient().fetchSchedule(using: creds)
            ScheduleCache.storeFromWidget(schedule: schedule, lunchMenu: nil, largeMode: largeMode.mode)
            return nil
        } catch {
            ScheduleCache.storeFromWidget(schedule: nil, lunchMenu: nil, largeMode: largeMode.mode)
            return ScheduleCache.load() == nil ? "Couldn't sync: \(error.localizedDescription)" : nil
        }
    }
}

public struct LunchWidgetIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource = "Lunch Menu"
    public static var description = IntentDescription("Your SchoolSoft login, used by the widget to sync directly.")

    @Parameter(title: "School URL")
    public var schoolURL: String?

    @Parameter(title: "Username")
    public var username: String?

    @Parameter(title: "Password")
    public var password: String?

    @Parameter(title: "Lunch Option", default: .normal)
    public var lunchMode: LunchModeOption

    public init() {}

    func refreshCache() async -> String? {
        guard let creds = WidgetSync.credentials(url: schoolURL, username: username, password: password) else {
            return WidgetSync.setupMessage
        }
        do {
            let menu = try await SchoolSoftClient().fetchLunchMenu(using: creds)
            ScheduleCache.storeFromWidget(schedule: nil, lunchMenu: menu, lunchMode: lunchMode.mode)
            return nil
        } catch {
            ScheduleCache.storeFromWidget(schedule: nil, lunchMenu: nil, lunchMode: lunchMode.mode)
            return ScheduleCache.loadLunchMenu() == nil ? "Couldn't sync: \(error.localizedDescription)" : nil
        }
    }
}
#endif
