# MyScreenTime Development Plan

## Progress legend

- [x] Completed
- [ ] Not completed

## Current progress

- [x] Created the local MyScreenTime project folder.
- [x] Initialized a Git repository with `main` as the default branch.
- [x] Connected the project to `git@github.com:Aymammet/MyScreenTime.git`.
- [x] Created and pushed the initial commit.
- [x] Created the initial `README.md`.
- [x] Documented the product requirements and development roadmap in `plan.md`.
- [x] Select native iOS/iPadOS and the SwiftUI technology stack.
- [x] Rebuild the project as a native Xcode application.
- [x] Begin MVP planning and document the primary user flow.
- [x] Complete the native iOS project foundation.
- [x] Begin parent profile and family setup.
- [x] Add SwiftData persistence for the local parent profile.
- [x] Add child creation and management.
- [x] Add device creation and management.
- [x] Build manual screen-time usage entry.
- [x] Add overlap detection and usage-session editing/deletion.
- [x] Calculate and display daily totals by child and device.
- [x] Test totals around midnight and time-zone boundaries.
- [x] Add separate weekday and weekend daily limits.
- [x] Add daily, weekly, and monthly dashboard summaries.
- [x] Add child device timers with completion notifications and automatic usage logging.
- [x] Add child settings for name, profile photo, limits, and individual usage summaries.
- [ ] Add analysis charts and previous-period comparisons.

**Current stage:** Phase 5 in progress — dashboard summaries and screen timers complete, charts and comparisons next

## 1. Product vision

MyScreenTime is a parent-focused application for tracking and managing children's daily screen time across multiple devices. Parents can manually record usage, see remaining allowance, review trends, and receive useful limit and comparison notifications.

## 2. Initial scope (MVP)

The first usable release will support:

- One local parent profile
- Multiple child profiles per parent
- Multiple devices per child
- Custom daily screen-time limits for each child
- Manual usage sessions with date, start time, and end time
- Automatic calculation of usage minutes
- A daily dashboard showing used and remaining time
- Usage history with editing and deletion
- Basic daily, weekly, and monthly analysis
- Notifications when limits are near, reached, or exceeded

## 3. Core data model

### Parent

- ID
- Name
- Email
- Authentication information
- Time zone
- Notification preferences
- Created and updated timestamps

### Child

- ID
- Parent ID
- Name
- Optional avatar or color
- Default daily limit in minutes
- Optional weekday and weekend limits
- Active status
- Created and updated timestamps

### Device

- ID
- Child ID
- Name
- Type: phone, tablet, PC, Chromebook, TV, game console, or other
- Optional icon or color
- Active status
- Created and updated timestamps

### Usage session

- ID
- Child ID
- Device ID
- Usage date
- Start time
- End time
- Calculated duration in minutes
- Optional note
- Created and updated timestamps

### Notification

- ID
- Parent ID
- Optional child ID
- Type
- Message
- Read status
- Created timestamp

## 4. Main screens

### Parent setup

- Parent name and preferences
- Notification preferences
- Optional Sign in with Apple and iCloud synchronization after the local MVP

### Parent dashboard

- List of children
- Today's total usage for each child
- Daily limit and remaining minutes
- Progress indicator with normal, near-limit, and exceeded states
- Quick action to add a usage session

### Child details

- Child profile and daily limit
- Today's total usage
- Remaining allowance
- Device list with usage per device
- Recent usage sessions
- Add, edit, and delete actions

### Add usage session

- Select child and device
- Select date
- Enter start and end times
- Preview automatically calculated duration
- Validate invalid and overlapping times
- Save the session and refresh totals

### Analysis

- Daily usage and average
- Weekly total and daily average
- Monthly total and daily average
- Previous-period comparison
- Breakdown by child and device
- Clear above-average and below-average messages

### Settings

- Manage parent profile
- Manage children and devices
- Configure daily limits
- Configure notification preferences
- Set time zone

## 5. Business rules

- End time must be later than start time unless overnight sessions are supported.
- Duration is calculated by the application and is not entered directly.
- Daily totals are calculated from all usage sessions for the child on that date.
- Remaining time equals the daily limit minus total usage, with zero shown once exceeded.
- The interface must also display the number of minutes over the limit.
- Overlapping sessions should show a warning and require correction for the MVP.
- Archived devices retain their historical usage records.
- All dates and notifications use the iOS device's current time zone.
- Weekday and weekend limits can be added after the basic daily-limit flow works.
- A child cannot have overlapping usage sessions in the MVP, including sessions on different devices.
- Daily limits apply to a child's combined usage across all devices in the MVP.
- Detailed decisions are recorded in `docs/product-decisions.md`.

## 6. Notification rules

Initial notification events:

- A child reaches 80% of the daily limit.
- A child reaches the daily limit.
- A child exceeds the daily limit.
- Monthly average is above or below the previous month.
- Monthly total reaches a configured monthly limit when monthly limits are added.

Notifications should not be repeatedly sent for the same threshold on the same day.

## 7. Implementation roadmap

### Phase 0 — Product decisions

- [x] Choose the first platform: native iOS and iPadOS application.
- [x] Choose Swift, SwiftUI, SwiftData, UserNotifications, and Swift Charts.
- [x] Use local-first storage; add optional iCloud synchronization after local flows are stable.
- [x] Prevent overlapping sessions so screen-time minutes are not counted twice.
- [x] Apply daily limits to each child's combined device usage in the MVP.
- [x] Create basic wireframes and define the primary user flow.

### Phase 1 — Project foundation

- [x] Create the native Xcode project and shared scheme.
- [x] Add the SwiftUI app and initial simulator screen.
- [x] Establish App, Design, Models, Services, Resources, and Tests folders.
- [x] Add initial child, device, and usage-session domain models.
- [x] Add Swift Testing unit tests and an XCUITest launch test.
- [x] Add an iOS continuous-integration workflow.
- [x] Document the Xcode build, run, and test workflow in `README.md`.

### Phase 2 — Parent and family setup

- [x] Implement the local parent profile and settings.
- [x] Add SwiftData persistence and a data-container configuration.
- [x] Add child creation, editing, archiving, and validation.
- [x] Add device creation, editing, archiving, and validation.
- [x] Add family setup navigation and empty states.
- [x] Add automated tests for parent, child, device, and persistence rules.
- [x] Add family management in Settings with child names and profile photos.

### Phase 3 — Screen-time tracking

- [x] Build the manual usage-entry form.
- [x] Calculate duration from start and end times.
- [x] Validate dates and time ranges.
- [x] Prevent overlapping sessions.
- [x] Add recent usage history.
- [x] Support editing and deleting usage sessions.
- [x] Calculate daily totals by child and device.
- [x] Add unit, persistence, and UI tests for initial usage entry and time calculations.

### Phase 4 — Dashboard and limits

- [x] Build the parent dashboard.
- [x] Display used, remaining, and over-limit minutes.
- [x] Add progress indicators and status colors.
- [x] Add daily-limit configuration.
- [x] Support weekday and weekend limits if included in the first release.
- [x] Test totals around midnight and time-zone boundaries.

### Phase 5 — Analysis

- [x] Build daily, weekly, and monthly summaries.
- [x] Calculate averages using clearly defined rules.
- [x] Show daily, weekly, and monthly totals for each child in Settings.
- [ ] Add charts for trends and device breakdowns.
- [ ] Compare the current period with the previous period.
- [ ] Handle incomplete weeks and months consistently.
- [ ] Verify calculations with representative test data.

### Phase 6 — Notifications

- [ ] Build in-app notifications.
- [x] Add local completion notifications for child screen timers.
- [ ] Add near-limit, reached-limit, and exceeded-limit events.
- [ ] Prevent duplicate threshold notifications.
- [ ] Add notification preferences.
- [ ] Add email or push notifications after in-app notifications are stable.

### Phase 7 — Quality, security, and release

- [ ] Add loading, empty, validation, and error states.
- [ ] Check keyboard navigation and screen-reader labels.
- [ ] Test responsive layouts on phone, tablet, and desktop sizes.
- [ ] Validate authorization and protect children's information.
- [ ] Add database backups and recovery guidance.
- [ ] Add end-to-end tests for primary workflows.
- [ ] Prepare staging and production environments.
- [ ] Complete a release checklist and deploy the MVP.

## 8. Recommended first user flow

1. Parent creates an account or signs in.
2. Parent adds a child and sets a daily limit.
3. Parent adds one or more devices for that child.
4. Parent records a device usage session.
5. The dashboard immediately updates used and remaining minutes.
6. Parent reviews the child's history and analysis.
7. The application creates notifications as thresholds are reached.

## 9. Testing priorities

- Duration calculations, including minute boundaries
- Overlapping sessions
- Sessions close to midnight
- Daylight-saving-time changes
- Editing and deleting sessions updates all totals
- Correct daily, weekly, and monthly aggregation
- Correct ownership and authorization between parent accounts
- No duplicate notifications
- Accessible and responsive interaction

## 10. Future possibilities

These are intentionally outside the initial MVP:

- Automatic collection from device operating systems
- Child accounts and child-facing views
- Multiple parents or guardians in one family
- Approval requests for additional screen time
- Per-device and per-category limits
- Rewards, chores, and earned screen time
- School-day, holiday, and vacation schedules
- Data export and printable family reports
- Localization and multiple languages
- Android application and remote push notifications

## 11. Immediate next steps

- [x] Confirm the native iOS platform and SwiftUI technology stack.
- [x] Agree on MVP boundaries and resolve initial business rules.
- [x] Create low-fidelity wireframes for the dashboard, child details, usage entry, and analysis screens.
- [x] Rebuild the application as native iOS and complete Phase 1.
- [x] Begin Phase 2 by implementing the local parent profile and SwiftData persistence.
- [x] Implement child creation, editing, archiving, and validation.
- [x] Implement device creation, editing, archiving, and validation.
- [x] Begin Phase 3 with the manual usage-entry form and automatic duration preview.
- [x] Add overlap detection, then support editing and deleting usage sessions.
- [x] Calculate daily totals by child and device.
- [x] Test totals around midnight and time-zone boundaries.
- [x] Add separate weekday and weekend daily limits.
- [x] Add daily, weekly, and monthly dashboard summaries.
- [x] Add child device timers with completion notifications and automatic usage logging.
- [x] Add child settings for name, profile photo, limits, and individual usage summaries.
- [ ] Add analysis charts and previous-period comparisons.

This document should be updated as requirements change and tasks are completed.

When a task is finished, change `- [ ]` to `- [x]` and update the **Current progress** section when the overall project stage changes.
