import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = AppearancePreference.system.rawValue
    @State private var largeWidgetMode: LargeWidgetMode = ScheduleCache.largeWidgetMode
    @State private var lunchMenuMode: LunchMenuMode = ScheduleCache.lunchMenuMode

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("App Theme", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.rawValue).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text("Controls the appearance of the main configuration window. The widget automatically follows your macOS system appearance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Large Widget") {
                Picker("Large Widget Shows", selection: $largeWidgetMode) {
                    ForEach(LargeWidgetMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: largeWidgetMode) { _, newValue in
                    ScheduleCache.largeWidgetMode = newValue
                }

                Text("\"This Week\" shows Monday–Friday side by side. \"Today Only\" shows a single larger agenda of just today's lessons, including when each one ends.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Lunch Menu") {
                Picker("Show", selection: $lunchMenuMode) {
                    ForEach(LunchMenuMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: lunchMenuMode) { _, newValue in
                    ScheduleCache.lunchMenuMode = newValue
                }

                Text("When a day lists a vegetarian alternative, this picks which one the lunch widget shows. Days with only one option are unaffected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
    }
}
