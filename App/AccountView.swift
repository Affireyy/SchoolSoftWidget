import SwiftUI
import WidgetKit

struct AccountView: View {
    @AppStorage("schoolURL") private var schoolURL = ""
    @AppStorage("username") private var username = ""
    @Environment(\.openWindow) private var openWindow
    @State private var password = ""
    @State private var isSyncing = false
    @State private var statusMessage = "Connect your SchoolSoft account to sync your schedule."
    @State private var statusType: StatusType = .info

    private enum StatusType {
        case info, success, error
    }

    private let liveService = SchoolSoftClient()
    private let mockService = MockSchoolSoftService()

    var body: some View {
        Form {
            Section("SchoolSoft Account") {
                TextField("School URL", text: $schoolURL, prompt: Text("https://sms13.schoolsoft.se/yourschool"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .onChange(of: username) { _, newUsername in
                        loadSavedPassword(for: newUsername)
                    }

                SecureField("Password", text: $password)
                    .textContentType(.password)

                Text("Your password is encrypted and stored exclusively in macOS Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Synchronization") {
                HStack(spacing: 12) {
                    Button(action: syncLiveSchedule) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text("Connect & Sync")
                    }
                    .disabled(isSyncing || schoolURL.isEmpty || username.isEmpty || password.isEmpty)
                    .keyboardShortcut(.defaultAction)

                    Button("Settings") {
                        openWindow(id: "settings")
                    }

                    Button("Refresh Widget", action: refreshWidget)
                        .disabled(isSyncing)
                }

                Label(statusMessage, systemImage: statusIcon)
                    .font(.footnote)
                    .foregroundStyle(statusColor)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .onAppear {
            loadSavedPassword(for: username)
        }
    }

    private var statusIcon: String {
        switch statusType {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch statusType {
        case .info: return .secondary
        case .success: return .green
        case .error: return .red
        }
    }

    private func loadSavedPassword(for user: String) {
        guard !user.isEmpty else { return }
        if let saved = KeychainHelper.get(for: user) {
            password = saved
        }
    }

    private func syncLiveSchedule() {
        guard !username.isEmpty, !password.isEmpty, !schoolURL.isEmpty else { return }

        // Save password securely to Keychain
        KeychainHelper.save(password: password, for: username)

        isSyncing = true
        statusType = .info
        statusMessage = "Connecting to SchoolSoft..."

        let creds = SchoolSoftCredentials(schoolURL: schoolURL, username: username, password: password)

        Task { @MainActor in
            do {
                let schedule = try await liveService.fetchSchedule(using: creds)
                ScheduleCache.save(schedule)
                statusType = .success
                statusMessage = "Successfully synchronized schedule (\(schedule.lessons.count) lessons found)."

                // Lunch menu is a nice-to-have alongside the class schedule: if it
                // fails (e.g. the endpoint/field mapping still needs tuning), don't
                // fail the whole sync over it — the schedule sync above already
                // succeeded and that's the important part.
                if let lunchMenu = try? await liveService.fetchLunchMenu(using: creds) {
                    ScheduleCache.save(lunchMenu)
                }
            } catch {
                ScheduleCache.recordError(error.localizedDescription)
                statusType = .error
                statusMessage = error.localizedDescription
            }
            isSyncing = false
        }
    }

    private func refreshWidget() {
        ScheduleCache.reloadWidgets()
        statusType = .info
        statusMessage = "Widget timeline refresh requested."
    }
}
