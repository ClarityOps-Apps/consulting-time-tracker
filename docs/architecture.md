# Architecture

Native Mac widget. SwiftUI views hosted in AppKit windows, plus an AppKit menu bar extra (`NSStatusItem`). The process is an accessory app (`LSUIElement`): no Dock icon. The Time window is shown on launch; **Show window** brings it back if it was closed.

## Storage

Local SQLite via the system `sqlite3` library. File path is Application Support (`Time/time.sqlite`), created on first launch. Git never holds hour data.

Tables:

- `entries` — finished intervals: start, end, duration in seconds, client, project, work type, billable
- `work_types` — editable names and sort order
- `running_session` — at most one in-progress interval, restored after relaunch
- `settings` — last form fields so Client / Project / Work type / Billable survive a quit

No backend, no iCloud, no accounts. Each Mac keeps its own file.

## Windows

AppDelegate owns three `NSWindow`s (Time ~280pt, History and Report ~400pt) and the status item. History and Report share one date-range type. Report CSV is written through `NSSavePanel`.

## Out of scope for v1

Calendar import. Client-vs-you / hide-internal-labels views. A Colors admin screen. Dock-first document UI.
