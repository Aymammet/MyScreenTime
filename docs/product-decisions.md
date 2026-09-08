# MyScreenTime MVP Product Decisions

## Platform

The first release will be a responsive web application. It will work on phones, tablets, Chromebooks, and desktop browsers from one codebase. Native mobile applications can be considered after the MVP is validated.

## Technology stack

- **Application:** Next.js with the App Router
- **Language:** TypeScript
- **Interface:** React, Tailwind CSS, and accessible reusable components
- **Database:** PostgreSQL
- **Database access:** Prisma ORM with migrations
- **Authentication:** Auth.js with email/password credentials for the MVP
- **Validation:** Zod schemas shared between forms and server actions
- **Unit and component testing:** Vitest and React Testing Library
- **End-to-end testing:** Playwright
- **Code quality:** ESLint and Prettier
- **Deployment target:** A managed web host and managed PostgreSQL provider, selected before production release

Exact package versions will be selected when the application framework is initialized.

## Data and synchronization

The MVP will use parent accounts and cloud storage. A signed-in parent can access the same family data from different browsers or devices. Local-only storage will not be the system of record.

## Screen-time counting

For the MVP, a child cannot have overlapping usage sessions, even when the sessions use different devices. This keeps the child's total screen time unambiguous and prevents the same minutes from being counted twice.

If a parent attempts to add an overlapping session, the application will identify the conflict and ask them to correct the entry.

## Limits

The MVP daily limit applies to the child's combined screen time across all devices. Device-level limits are deferred until after the MVP.

The dashboard will show:

- Total minutes used
- Daily limit
- Minutes remaining
- Minutes over the limit, when applicable
- Usage broken down by device

## Time rules

- Usage is stored as a start timestamp and end timestamp.
- Duration is calculated, not manually entered.
- Overnight sessions are not supported in the initial entry form; a parent records them as two sessions split at midnight.
- Daily totals follow the parent's configured time zone.
- Archived children and devices retain historical records.

## Primary user flow

1. A parent creates an account or signs in.
2. The parent adds a child and sets a combined daily limit.
3. The parent adds the child's devices.
4. The parent records a usage session by choosing a device and entering its start and end times.
5. The dashboard immediately updates used and remaining time.
6. The parent reviews usage history and analysis.
7. The application creates an in-app notification when a configured threshold is reached.

## MVP boundary

The MVP includes manual tracking, combined child limits, analysis, and in-app notifications. Automatic device monitoring, child accounts, multiple guardians, device-level limits, native applications, and push notifications remain future work.
