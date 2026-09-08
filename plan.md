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
- [x] Select the application platform and technology stack.
- [x] Initialize the application framework.
- [x] Begin MVP planning and document the primary user flow.
- [x] Complete the Phase 1 project foundation.
- [ ] Begin Phase 2 accounts and family setup.

**Current stage:** Phase 1 complete — ready for accounts and family setup

## 1. Product vision

MyScreenTime is a parent-focused application for tracking and managing children's daily screen time across multiple devices. Parents can manually record usage, see remaining allowance, review trends, and receive useful limit and comparison notifications.

## 2. Initial scope (MVP)

The first usable release will support:

- One parent account with secure sign-in
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

### Authentication

- Sign up
- Sign in
- Sign out
- Password recovery

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
- All dates and notifications use the parent's configured time zone.
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

- [x] Choose the first platform: responsive web application.
- [x] Choose the technology stack.
- [x] Use cloud accounts and synchronized cloud storage.
- [x] Prevent overlapping sessions so screen-time minutes are not counted twice.
- [x] Apply daily limits to each child's combined device usage in the MVP.
- [x] Create basic wireframes and define the primary user flow.

### Phase 1 — Project foundation

- [x] Initialize the selected application framework.
- [x] Add formatting, linting, and test tooling.
- [x] Configure environment variables and provide an example environment file.
- [x] Establish the folder structure and coding conventions.
- [x] Create the database schema and initial migration.
- [x] Add a continuous-integration workflow.
- [x] Document local setup and development commands in `README.md`.

### Phase 2 — Accounts and family setup

- [ ] Implement parent authentication.
- [ ] Implement parent profile settings.
- [ ] Add child creation, editing, archiving, and validation.
- [ ] Add device creation, editing, archiving, and validation.
- [ ] Ensure parents can access only their own family data.
- [ ] Add automated tests for account and ownership rules.

### Phase 3 — Screen-time tracking

- [ ] Build the manual usage-entry form.
- [ ] Calculate duration from start and end times.
- [ ] Validate dates, times, and overlapping sessions.
- [ ] Add usage history.
- [ ] Support editing and deleting usage sessions.
- [ ] Calculate daily totals by child and device.
- [ ] Add unit and integration tests for time calculations.

### Phase 4 — Dashboard and limits

- [ ] Build the parent dashboard.
- [ ] Display used, remaining, and over-limit minutes.
- [ ] Add progress indicators and status colors.
- [ ] Add daily-limit configuration.
- [ ] Support weekday and weekend limits if included in the first release.
- [ ] Test totals around midnight and time-zone boundaries.

### Phase 5 — Analysis

- [ ] Build daily, weekly, and monthly summaries.
- [ ] Calculate averages using clearly defined rules.
- [ ] Add charts for trends and device breakdowns.
- [ ] Compare the current period with the previous period.
- [ ] Handle incomplete weeks and months consistently.
- [ ] Verify calculations with representative test data.

### Phase 6 — Notifications

- [ ] Build in-app notifications.
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
- Native mobile applications and push notifications

## 11. Immediate next steps

- [x] Confirm the initial platform and technology stack.
- [x] Agree on MVP boundaries and resolve initial business rules.
- [x] Create low-fidelity wireframes for the dashboard, child details, usage entry, and analysis screens.
- [x] Initialize the application and complete Phase 1.
- [ ] Begin Phase 2 by implementing parent authentication.

This document should be updated as requirements change and tasks are completed.

When a task is finished, change `- [ ]` to `- [x]` and update the **Current progress** section when the overall project stage changes.
