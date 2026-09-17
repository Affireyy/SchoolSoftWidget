import Sparkle
import SwiftUI

@main
struct SchoolSoftWidgetApp: App {
    @AppStorage("appearance") private var appearance = AppearancePreference.system.rawValue

    // Starts Sparkle's background update checker immediately. Feed URL and
    // the public signing key live in Info.plist (SUFeedURL / SUPublicEDKey,
    // set via project.yml) rather than here.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            AccountView()
                .preferredColorScheme(AppearancePreference(rawValue: appearance)?.colorScheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Schedule") {
                Button("Reload Widget Timelines") {
                    ScheduleCache.reloadWidgets()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(AppearancePreference(rawValue: appearance)?.colorScheme)
        }
    }
}


enum AppearancePreference: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
