import AppKit
import SwiftUI
import WidgetKit

/// Diagnostic and developer-facing settings that a normal user shouldn't
/// need to find day to day -- kept separate from the regular Settings
/// window so that one stays focused on the handful of options someone
/// actually wants to change. Reached via the app menu's "Advanced
/// Settings…" item (Cmd+,), which used to open this content's regular
/// counterpart before the two were split apart.
struct AdvancedSettingsView: View {
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Shared Cache") {
                LabeledContent("Cache File Location", value: ScheduleCache.sharedCacheDirectoryPath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)

                LabeledContent("Schedule Cached", value: ScheduleCache.load() != nil ? "Yes" : "No")
                LabeledContent("Lunch Menu Cached", value: ScheduleCache.loadLunchMenu() != nil ? "Yes" : "No")

                if let date = ScheduleCache.lastSyncDate {
                    LabeledContent("Last Synced", value: date.formatted(date: .abbreviated, time: .shortened))
                }

                if let error = ScheduleCache.lastError {
                    LabeledContent("Last Sync Error", value: error)
                        .foregroundStyle(.red)
                }

                Button("Reveal Cache Folder in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ScheduleCache.sharedCacheDirectoryPath)
                }
                .font(.footnote)
            }

            Section("Widget") {
                Text("WidgetKit updates are scheduled based on lesson transition times and macOS budget policies, so a manual refresh is rarely needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Force Reload Widget Timelines") {
                    ScheduleCache.reloadWidgets()
                    statusMessage = "Requested a widget timeline reload."
                }
                .font(.footnote)
            }

            Section("Developer / Testing") {
                Text("Loads placeholder data so you can preview the widgets without a real SchoolSoft account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Load Sample Schedule") {
                    loadSampleSchedule()
                }
                .font(.footnote)
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }

    private func loadSampleSchedule() {
        let sample = Schedule.sample
        ScheduleCache.save(sample)
        ScheduleCache.save(LunchMenu.sample)
        statusMessage = "Loaded sample schedule with \(sample.lessons.count) lessons for testing."
    }
}
