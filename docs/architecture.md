# Architecture

Native Mac widget. SwiftUI views hosted in AppKit windows, plus an AppKit menu bar extra (`NSStatusItem`). The process is an accessory app (`LSUIElement`): no Dock icon. The Time window is shown on launch; **Show window** brings it back if it was closed.

Open `Time.xcodeproj` in Xcode when it is installed. Without Xcode, `./scripts/package-app.sh` compiles a runnable `Time.app` with `swiftc` and Command Line Tools.

## Storage

Local SQLite via the system `sqlite3` library. File path is Application Support (`Time/time.sqlite`), created on first launch. Git never holds hour data.

Tables:

- `entries` — finished intervals: start, end, duration in seconds, client, project, work type, billable
- `work_types` — editable names and sort order
- `running_session` — at most one in-progress interval, restored after relaunch
- `settings` — last form fields

No backend, no iCloud. Each Mac keeps its own file.

Harvest connect (Personal Access Token + Account ID) lives in the Colors window. Credentials are stored in the Mac Keychain, never in SQLite or git. Pull copies active clients, projects, and tasks (Work type) into the existing lists. Hours are not sent back.

## Windows

AppDelegate owns three `NSWindow`s (Time ~280pt, History and Report ~400pt) and the status item. History and Report share one date range. Report CSV is written through `NSSavePanel`. The four look colors (Font, Action, Quiet, Window) are tokens in the app, not an admin screen.

## Out of scope for v1

Calendar import. Client-vs-you / hide-internal-labels views. Dock-first document UI.
