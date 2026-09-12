# MyScreenTime iOS MVP Wireframes

These low-fidelity wireframes define information hierarchy and primary actions. They are not final visual designs.

## 1. Parent dashboard

```text
┌─────────────────────────────────────────────────────────────┐
│ MyScreenTime                     Analysis   Alerts   Profile │
├─────────────────────────────────────────────────────────────┤
│ Today                                      + Add screen time │
│                                                             │
│ ┌─ Alex ───────────────────────────────────────────────────┐ │
│ │ 75 of 120 min used                         45 min left   │ │
│ │ ███████████████████░░░░░░░░░░░                         │ │
│ │ Phone 45 min  ·  Chromebook 30 min            View →    │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ Maya ───────────────────────────────────────────────────┐ │
│ │ 105 of 90 min used                       15 min over     │ │
│ │ █████████████████████████████████████                   │ │
│ │ TV 60 min  ·  Tablet 45 min                  View →     │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ + Add child                                                 │
└─────────────────────────────────────────────────────────────┘
```

## 2. Child details

```text
┌─────────────────────────────────────────────────────────────┐
│ ← Children                         Alex          Edit profile │
├─────────────────────────────────────────────────────────────┤
│ TODAY                                                       │
│ 75 min used          45 min left          Limit: 120 min    │
│ ███████████████████░░░░░░░░░░░                             │
│                                             + Add session    │
├─────────────────────────────────────────────────────────────┤
│ Devices                                                     │
│ ┌ Phone ─────────── 45 min ─────────────── View history ┐    │
│ └ Chromebook ────── 30 min ─────────────── View history ┘    │
│ + Add device                                                │
├─────────────────────────────────────────────────────────────┤
│ Recent sessions                                             │
│ Phone        11:00 AM–11:30 AM       30 min       Edit      │
│ Chromebook    9:15 AM– 9:45 AM       30 min       Edit      │
└─────────────────────────────────────────────────────────────┘
```

## 3. Add usage session

```text
┌───────────────────────────────────────────┐
│ Add screen time                       ×   │
├───────────────────────────────────────────┤
│ Child      [ Alex                    ▾ ]  │
│ Device     [ Phone                   ▾ ]  │
│ Date       [ Today                   ▾ ]  │
│ Start      [ 11:00 AM                  ]  │
│ End        [ 11:30 AM                  ]  │
│                                           │
│ Duration: 30 minutes                      │
│                                           │
│ [ Cancel ]               [ Save session ] │
└───────────────────────────────────────────┘

Validation appears beside the affected field. An overlap message identifies the conflicting session.
```

## 4. Analysis

```text
┌─────────────────────────────────────────────────────────────┐
│ Analysis                   Child: Alex ▾     This month ▾    │
├─────────────────────────────────────────────────────────────┤
│ Daily average      Weekly average       Monthly total        │
│ 82 min             574 min              2,460 min            │
│                                                             │
│ Usage trend                                                 │
│ 120 ┤              ╭─╮                                     │
│  90 ┤    ╭─╮   ╭───╯ ╰─╮                                   │
│  60 ┤╭───╯ ╰───╯       ╰──                                 │
│   0 └────────────────────────                                │
│                                                             │
│ 8% below last month                                         │
│                                                             │
│ By device                                                   │
│ Phone        ███████████████  52%                            │
│ Chromebook   █████████        31%                            │
│ TV           █████            17%                            │
└─────────────────────────────────────────────────────────────┘
```

## 5. iPhone tab navigation

```text
┌──────────────────────────────┐
│ Current screen content       │
│                              │
│                              │
├──────────────────────────────┤
│ Home   Analysis   Alerts   Me│
└──────────────────────────────┘
```

The primary **Add screen time** action remains prominent on the dashboard and child-details screen. On iPad, the same destinations can move into a sidebar while preserving the screen hierarchy.
