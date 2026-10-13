# BrightTime: Vision and Future Steps

_Saved Oct 11, 2026. A parked plan to come back to; nothing here is in progress yet._
_Living version: "BrightTime: Plan to Lead the Category" doc in the BrightTime project._

## The bet

BrightTime becomes the family's shared screen-time ledger for **every screen in the house**, run by **both parents**, where kids **earn** time instead of only losing it.

Phone-blocking apps (Apple Screen Time, Family Link, Qustodio, Bark) control one child's phone. None of them see the TV, the Switch or the shared iPad, and none treat co-parents or a kid's good behaviour as first-class. Apple keeps making blocking free, so we compete on the family around the blocking, not on blocking alone.

Three moves matter most:

1. **Effortless logging everywhere.** Widgets, Live Activity and Siri are built. Next: Apple Watch, Control Center, NFC tags.
2. **Make the kid a user.** Kid companion app: time left, time bank, "Ask for 15 more minutes", parent approves from a notification.
3. **Real enforcement on kids' iPhones** through Apple's Screen Time API (Family Controls). Request the distribution entitlement early; approval takes weeks.

## Where BrightTime stands (Oct 2026)

| | Apple / Family Link | Qustodio | Bark | Chore apps | BrightTime |
| --- | --- | --- | --- | --- | --- |
| Blocks apps on kid's phone | Yes | Yes | Partly | No | Planned |
| TV, console, shared tablet | No | No | No | No | **Yes** |
| Two parents, one view | One organizer | Paid | Paid | Rarely | **Yes (iCloud)** |
| Kids earn time | No | No | No | Yes | **Yes (time bank)** |
| Kid can ask for more | Yes | Yes | No | No | Not yet |
| Widgets, Live Activity, Siri | System | Limited | Limited | Rarely | **Yes** |
| Price | Free | $59.95–$104.95/yr | $49–$99/yr | Small | Free so far |

## Positioning

**For** parents of kids about 5 to 13 who share TVs, consoles and tablets, **BrightTime** is the one place both parents see and manage every screen, where kids earn their time.

App Store line: _"Screen time for the whole house. Every screen, both parents, time kids earn."_

We won't: spy on messages, fight Apple with VPN/MDM tricks, or sell data / show ads.

Beachhead: families with consoles and a shared TV, and two-household / separated parents.

## Roadmap (move on only when the gate is passed)

| Phase | When | Build | Gate to the next phase |
| --- | --- | --- | --- |
| 1 · Launch-ready | First 30 days | Co-parent sync tested on real iPhones · subscriptions and paywall · privacy policy · TestFlight with 10 families | 5 of 10 families still logging after 2 weeks |
| 2 · Habit | Months 1–3 | Kid companion + Ask for more · Apple Watch, Control Center · NFC tags to start a timer · Monday weekly report | Day-30 retention at 35% or more |
| 3 · Control | Months 3–6 | Limits on kids' iPhones (Screen Time API) · auto-tracked iPhone/iPad use · bedtime and school schedules · public App Store launch | Family Controls entitlement approved |
| 4 · Network | Months 6–12 | Share cards and referrals · grandparent and sitter roles · web viewer for Android co-parents · year-in-review | — |

## Moats

1. **Family history**: months of logs, streaks and time-bank records; show it back (monthly reports, year-in-review).
2. **Two-parent network**: every invite adds a second adult who depends on the app.
3. **The kid's buy-in**: kids push to keep an app that lets them earn time.
4. **Native Apple polish**: SwiftUI, widgets, Live Activities, Watch, Siri.

Don't rely on any single feature, enforcement included; Apple can ship it free.

## Pricing (starting point)

| Plan | Price | Includes |
| --- | --- | --- |
| Free | $0 | 1 kid, unlimited devices and timers, widgets, Live Activity, Siri, 7 days of history |
| Premium monthly | $3.99/mo | Unlimited kids, co-parent sync, time bank, full history and reports, kid companion |
| Premium yearly | $29.99/yr | Same, ~37% cheaper; default on the paywall |
| Lifetime (launch only) | $69.99 once | Early fans; time-limited |

Paywall at: second kid, co-parent invite, history older than 7 days. Never block logging. 14-day trial. Turn on Family Sharing for the subscription.

## Growth

- **Loops:** co-parent invite right after setup · kid companion on the family iPad · shareable "earned 2h by reading" cards · referral = free month for both.
- **ASO phrases:** "TV time limit", "Xbox time limit", "Switch screen time", "chore chart screen time", "co-parenting screen time". Screenshots show a TV and a console.
- **Channels:** short video (TikTok, Reels, Shorts) with parent creators · parent Facebook groups, r/Parenting, r/coparenting · family therapists and mediators · launch around back-to-school or the holidays.
- **Start local:** Ontario / GTA schools, parent groups, community centres.

## Metrics (first targets, revise after 500 families)

| Metric | Target |
| --- | --- |
| Weekly active families (3+ sessions/week) — north star | 1,000 by month 6 |
| Setup done on day 1 | 60% of installs |
| Day-30 retention | 35% |
| Families with a co-parent | 25% |
| Families using the time bank | 30% |
| Sessions started from widget / Siri / Live Activity | 40% |
| Free to paid within 60 days | 4–6% |
| App Store rating | 4.7+ |

Count on device, send only anonymous totals.

## Risks

| Risk | Plan |
| --- | --- |
| Manual logging fades (biggest risk) | One-tap logging everywhere; kids start their own timers; weekly recap |
| Apple ships it free | Stay where Apple won't go: non-Apple screens, two households, earned time |
| Family Controls entitlement slow/refused | Apply early; enforcement is an add-on, app works without it |
| Sync bugs | Test on two real iPhones; keep conflicts visible and recoverable |
| Kids' privacy laws (COPPA, PIPEDA) | Data on device + family iCloud; no kid analytics; get a privacy lawyer's review |
| iOS-only while co-parents use Android | Measure failed invites; web/Android viewer in year two |
| Too many ideas for two founders | One phase at a time, gated |

## When we come back: first two weeks

- [ ] Push local commits to GitHub
- [ ] Register iCloud container + App Group; test co-parent sync on two iPhones with different Apple IDs
- [ ] Deploy CloudKit schema to Production
- [ ] Request the Family Controls distribution entitlement
- [ ] StoreKit 2 subscriptions + paywall
- [ ] One-page privacy policy
- [ ] TestFlight Build 3 to 10 families (3+ with consoles, 2+ two-household)
- [ ] One-week interviews: what they logged, skipped, would pay
- [ ] New App Store screenshots around TVs and consoles; pick 5 search phrases
- [ ] Decide next build from interviews: kid companion or Apple Watch

## Sources

- [iOS 26 parental controls](https://www.fox29.com/news/apple-parental-controls-ios26), FOX 29
- [Configuring Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls), Apple Developer
- Competitor prices and complaints: Oct 2026 market research in the BrightTime project (`claude/market-positioning-and-bug-audit.md`)
