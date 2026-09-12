# MyScreenTime iOS Product Decisions

## Platform

MyScreenTime will be a native iOS and iPadOS application built and tested in Xcode. The first release targets iOS 17 or newer and uses one SwiftUI codebase for iPhone and iPad.

## Technology stack

- **Language:** Swift 6
- **Interface:** SwiftUI
- **Architecture:** Feature-oriented MVVM with small observable state objects
- **Local persistence:** SwiftData
- **Optional synchronization:** CloudKit through SwiftData after local flows are stable
- **Notifications:** UserNotifications for local limit alerts
- **Charts:** Swift Charts
- **Unit tests:** Swift Testing
- **UI tests:** XCTest and XCUITest
- **Dependencies:** Apple frameworks first; third-party packages only when they provide clear value

## Account approach

The first simulator-testable MVP will work locally without requiring account creation. A parent profile will represent the device owner. Sign in with Apple and iCloud synchronization can be added after local family setup and tracking are stable.

## Screen-time counting

A child cannot have overlapping usage sessions, even when the sessions use different devices. This prevents the same minutes from being counted twice.

## Limits

The MVP daily limit applies to the child's combined screen time across all devices. Device-level limits are deferred until after the MVP.

## Time rules

- A usage session stores a start date and end date.
- Duration is calculated and rounded up to the next whole minute.
- End time must be later than start time.
- Overnight sessions are entered as two sessions split at midnight in the MVP.
- Archived children and devices retain their historical records.
- Calendar calculations use the device's current time zone.

## Testing workflow

Each milestone must remain runnable in the iOS Simulator. The expected workflow is:

1. Open the Xcode project.
2. Select an iPhone simulator.
3. Build and run with `⌘R`.
4. Manually test the new user flow.
5. Run automated tests with `⌘U`.
6. Commit only after the milestone builds and tests pass.

## MVP boundary

The MVP includes local parent settings, child and device management, manual screen-time tracking, combined child limits, analysis, and local notifications. Automatic device monitoring, child accounts, multiple guardians, device-level limits, Android support, and remote push notifications remain future work.
