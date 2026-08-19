# Time

A native Mac widget that logs consulting hours. Menu bar plus an always-on window titled Time. Manual start and stop. Hours and minutes stay on this Mac in local SQLite.

GitHub is the source of truth. There is no backend, no iCloud, and no accounts. Calendar import is later, not in this version.

## How to run

Open `Time.xcodeproj` in Xcode (macOS 14+) and run the **Time** scheme.

If Xcode is not installed and you have Command Line Tools plus Swift, you can still assemble a local app:

```
./scripts/package-app.sh
open Time.app
```

The app is an accessory process (no Dock icon). After it launches you should see a clock in the menu bar and the Time window.

## Where data lives

SQLite lives in Application Support, never in this repo.

- Sandboxed build: `~/Library/Containers/co.clarityops.Time/Data/Library/Application Support/Time/time.sqlite`
- Unsandboxed / script-built app: `~/Library/Application Support/Time/time.sqlite`

Hours, the work-type list, and a running session (so a relaunch can keep timing) are stored there.

## Work type

The Work type popup ships this editable starter list: Research, Meetings, Admin, Project Management, Analysis, Documentation, Client Communication, Business Development, Training.

Use **Edit list…** to add, rename, or remove names. These are starters, not a locked product list.

## What it does

- **Time** window: start and stop, Work type, Client, Project, Billable, and a Today total that includes a running session.
- **Menu bar:** clock icon plus elapsed (`1:24` while running). Menu: Start or Stop, Show window, History, Report, Quit.
- **History:** date range, foldable By client totals (client + hours only), chronological entries.
- **Report:** same date range, nested client → project → work type, **Save CSV** (client, project, work type, hours and minutes).

Date ranges: Today, This week, Last week, This month, Choose dates.

## Bundle

- Window title: Time
- Bundle id: `co.clarityops.Time`
- macOS 14+
