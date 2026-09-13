# MyScreenTime

MyScreenTime is a native iOS application that helps parents track and manage children's daily screen time across phones, tablets, computers, Chromebooks, televisions, and game consoles.

## Technology

- Swift 6
- SwiftUI
- Xcode 26
- iOS 17 or newer
- Swift Testing for unit tests
- XCTest for UI tests

SwiftData provides local persistence. Optional iCloud synchronization can be added after the local family-management flows are stable.

## Open and run in Xcode

1. Open `MyScreenTime.xcodeproj` in Xcode.
2. Select the **MyScreenTime** scheme.
3. Select an iPhone simulator, such as **iPhone 17 Pro**.
4. Press **Run** (`⌘R`).
5. Create the local parent profile shown on first launch.

After setup, add a child and choose one limit for every day or separate weekday and weekend limits. The parent dashboard shows today's combined usage, remaining allowance, and limit status for every child. Tap a child to see the same daily summary plus today's subtotal for each device. Use **Record screen time** to choose a device, date, start time, and end time; totals refresh automatically after saving, editing, or deleting a session. The calculated minutes appear before saving, and overlapping sessions for the same child are blocked across all devices. Saved sessions appear under **Recent usage**: tap one to edit it or swipe left to delete it with confirmation. Tap a device to edit it, or swipe a child or device left to edit or archive it. Close and reopen the app to verify that SwiftData restores the family and usage history.

The main dashboard also shows today's usage, this week's total and daily average, and this month's total and daily average. Use **Start timer** on a child row to select a device and duration. While running, the compact child card shows the countdown on the right, a **Stop timer** action beneath it, and session progress along the bottom. Stopping early records elapsed time and cancels the pending completion notification. The timer survives app restarts, sends a local notification when it ends, and adds the completed duration to the child's usage automatically when the app is active or next opened.

Open **Settings** and select a child to edit their name, choose or remove a profile photo, update their limits, and review that child's usage for today, this week, and this month. Profile photos are resized before being stored locally and appear on the main dashboard and child detail screen.

No external packages, environment variables, or database are required.

## Run tests in Xcode

Press **Test** (`⌘U`) to run:

- Three unit tests for usage-duration calculations
- Seventeen tests for persistence, profile photos, overlap detection, aggregation, analysis periods, time zones, limits, and timers
- One UI test covering setup, overlap rejection, usage editing, and confirmed deletion

## Command-line verification

```bash
xcodebuild test \
  -project MyScreenTime.xcodeproj \
  -scheme MyScreenTime \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

## Project structure

```text
MyScreenTime/App/          App entry point and SwiftUI screens
MyScreenTime/Design/       Colors and reusable design values
MyScreenTime/Models/       Child, device, and usage-session models
MyScreenTime/Services/     Business calculations and app services
MyScreenTime/Resources/    Asset catalogs and bundled resources
MyScreenTimeTests/         Unit tests
MyScreenTimeUITests/       Simulator UI tests
docs/                      Product decisions and wireframes
```

## Development workflow

- Implement one small feature at a time.
- Build after each meaningful change with `⌘B`.
- Run the app in the simulator with `⌘R`.
- Run tests with `⌘U` before committing.
- Update `plan.md` whenever a roadmap task is completed.
