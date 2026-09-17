# SchoolSoft Widget (macOS)

A native macOS-only schedule widget and companion settings application built with **Swift**, **SwiftUI**, and **WidgetKit**.

The main macOS app is deliberately minimal and conventional: it provides SchoolSoft account authentication, secure Keychain storage, sync controls, and appearance customization. The schedule itself is presented natively in the macOS Notification Center and Desktop via WidgetKit.

---

## Architecture & Features

- **Native macOS & WidgetKit**: Built with pure SwiftUI and WidgetKit; supports `.systemSmall`, `.systemMedium`, and `.systemLarge` widget sizes.
- **Dynamic Timeline Transitions**: The widget calculates timeline entries at the exact start and end boundaries of every lesson today, ensuring immediate status transitions without battery-draining polling.
- **Shared App Group Container**: Schedule data and synchronization status are shared between the main app and the widget extension via `ScheduleCache` backed by an App Group.
- **Encrypted Keychain Storage**: Passwords and authentication tokens are encrypted and managed strictly in macOS Keychain via `KeychainHelper`, never in plaintext or `UserDefaults`.
- **Flexible SchoolSoft Service**:
  - `SchoolSoftClient`: Direct integration with SchoolSoft mobile REST API endpoints (`/rest/app/login` and `/rest/app/lessons`).
  - `MockSchoolSoftService`: Offline testing service for sample schedules.
  - "Load Sample Schedule" button in the app for testing widget layouts immediately without live school credentials.
- **Reproducible XcodeGen Toolchain**: Both the application and the widget extension targets, capabilities, entitlements, and embedding rules are defined in `project.yml`.

---

## Project Structure

```
SchoolSoftWidgetStarter/
├── App/                                # Main macOS configuration app
│   ├── SchoolSoftWidgetApp.swift       # App lifecycle, scenes, and keyboard shortcuts
│   ├── AccountView.swift               # SchoolSoft login form, Keychain sync, status
│   ├── SettingsView.swift              # Theme preferences & system diagnostics
│   └── SchoolSoftWidget.entitlements   # App Sandbox, Network Client, App Group
│
├── Widget/                             # macOS WidgetKit Extension
│   ├── ScheduleWidget.swift            # TimelineProvider, Small/Medium/Large views, Previews
│   ├── Info.plist                      # WidgetKit extension point declaration
│   ├── Assets.xcassets                 # Widget icons and color sets
│   └── SchoolSoftWidgetExtension.entitlements # App Sandbox, App Group
│
├── Shared/                             # Shared business logic and data layer
│   ├── Schedule.swift                  # Schedule & Lesson models, active/upcoming helpers
│   ├── ScheduleCache.swift             # App Group cache persistence & Widget reload triggers
│   ├── KeychainHelper.swift            # Secure macOS Keychain wrapper
│   └── SchoolSoftScheduleService.swift # API client protocol, DTOs, live and mock clients
│
├── project.yml                         # Complete XcodeGen specification
└── SchoolSoftWidget.xcodeproj          # Generated Xcode project
```

---

## Practical Toolchain & Prerequisites

### 1. Requirements
- macOS 14.0 (Sonoma) or newer.
- Xcode 15+ installed at `/Applications/Xcode.app`.
- XcodeGen:
  ```sh
  brew install xcodegen
  ```

### 2. Generate the Xcode Project
From the repository root:
```sh
xcodegen generate
```
XcodeGen reads `project.yml` and generates `SchoolSoftWidget.xcodeproj` containing both the main app target and the properly embedded widget extension.

### 3. Building via Terminal
To build using the command line without signing (e.g. in CI or local terminal):
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SchoolSoftWidget.xcodeproj \
  -scheme SchoolSoftWidget \
  -derivedDataPath .derivedData \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

---

## Opening, Signing, and Testing in Xcode

### 1. Code Signing in Xcode
1. Open `SchoolSoftWidget.xcodeproj` in Xcode.
2. Select the top-level project in the Project Navigator.
3. Under the **Signing & Capabilities** tab:
   - For **`SchoolSoftWidget`**: Select your Apple Development Team (or Personal Team) and verify **Automatic Signing** is checked.
   - For **`SchoolSoftWidgetExtension`**: Select the same Team.
   - Both targets will automatically share the App Group `UDWA7LNKRM.com.dessimondi.SchoolSoftWidget` (or your configured team prefix).

### 2. Interactive Widget Previews
- Open `Widget/ScheduleWidget.swift` in Xcode.
- The built-in Canvas displays real-time interactive previews for **Small**, **Medium**, and **Large** widget configurations using sample schedule entries.

### 3. Running the App and Installing the Widget
1. Select the `SchoolSoftWidget` scheme in Xcode's toolbar and press **Cmd+R** to run.
2. In the app window:
   - Enter your SchoolSoft URL and credentials to sync live, or click **Load Sample Schedule** to populate test lessons immediately.
3. Open macOS **Notification Center** (click the clock/date in the top-right corner of the menu bar).
4. Click **Edit Widgets** at the bottom.
5. Select **SchoolSoftWidget** in the widget sidebar and drag the desired size (Small, Medium, Large) to your desktop or Notification Center.
6. Press **Cmd+R** in the main app to reload the widget timeline at any time.

---

## Installing (for end users)

1. Grab the latest `SchoolSoftWidget-*.dmg` from [Releases](https://github.com/Affireyy/SchoolSoftWidget/releases).
2. Open the DMG and drag **SchoolSoftWidget** into **Applications**.
3. First launch only: this build isn't signed with a paid Apple Developer ID
   (see below), so Gatekeeper will call it "unidentified developer." Right-click
   the app in Applications and choose **Open**, then confirm once. Every
   launch after that works normally, including double-click.

## Auto-updates

The app checks GitHub in the background via [Sparkle](https://sparkle-project.org)
and offers to download and install new versions automatically -- no need to
revisit this repo or re-download the DMG by hand. You can also trigger a check
manually from the app's menu: **SchoolSoftWidget > Check for Updates…**.
