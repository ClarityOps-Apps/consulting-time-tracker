import Foundation
import Combine
import SwiftUI

final class TimeStore: ObservableObject {
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var runningStartedAt: Date?
    @Published var sessionStartedAt: Date?
    @Published var heldSeconds = 0
    @Published var workType = ""
    @Published var client = ""
    @Published var project = ""
    @Published var billable = false
    @Published var workTypes: [WorkTypeItem] = []
    @Published var entries: [TimeEntry] = []
    @Published var now = Date()
    @Published var palette = Palette()
    @Published var dateRange: DateRangeKind = .thisWeek
    @Published var customStart = Date()
    @Published var customEnd = Date()
    var onOpenWorkTypes: (() -> Void)?
    var onOpenColors: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onOpenWorkTypeMenu: (() -> Void)?

    private let db: Database
    private var tickTimer: Timer?
    var dataFileURL: URL { db.fileURL }

    init() {
        do {
            db = try Database()
        } catch {
            fatalError("Time could not open its local database: \(error)")
        }
        reload()
        restoreSession()
        restoreHeld()
        startTicking()
        observeForm()
    }

    private func observeForm() {
        Publishers.CombineLatest4($workType, $client, $project, $billable)
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.persistFormAndRunning()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func startTicking() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    var displaySeconds: Int {
        var live = 0
        if isRunning, let start = runningStartedAt {
            live = max(0, Int(now.timeIntervalSince(start)))
        }
        return max(0, heldSeconds + live)
    }

    var runningSubtitle: String {
        let parts = [client, workType]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    var todaySeconds: Int {
        let (start, end) = DateRangeKind.today.bounds(now: now)
        let finished = entries
            .filter { $0.startedAt >= start && $0.startedAt < end }
            .reduce(0) { $0 + $1.durationSeconds }
        return finished + ((isRunning || isPaused) ? displaySeconds : 0)
    }

    func entries(in range: DateRangeKind, customStart: Date, customEnd: Date) -> [TimeEntry] {
        let (start, end) = range.bounds(now: now, customStart: customStart, customEnd: customEnd)
        return entries.filter { $0.startedAt >= start && $0.startedAt < end }
    }

    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        if isRunning { return }
        now = Date()
        if !isPaused {
            sessionStartedAt = now
            heldSeconds = 0
        }
        runningStartedAt = now
        isRunning = true
        isPaused = false
        persistFormAndRunning()
        persistHeld()
        objectWillChange.send()
    }

    func pause() {
        guard isRunning, let start = runningStartedAt else { return }
        heldSeconds += max(0, Int(Date().timeIntervalSince(start)))
        isRunning = false
        isPaused = true
        runningStartedAt = nil
        persistHeld()
        persistForm()
        do { try db.clearRunningSession() } catch {
            NSLog("Time: could not clear running session: \(error)")
        }
        objectWillChange.send()
    }

    func stop() {
        guard isRunning || isPaused else { return }
        let end = Date()
        var seconds = heldSeconds
        if isRunning, let start = runningStartedAt {
            seconds += max(0, Int(end.timeIntervalSince(start)))
        }
        let start = sessionStartedAt ?? runningStartedAt ?? end
        do {
            try db.insertEntry(
                startedAt: start,
                endedAt: end,
                durationSeconds: seconds,
                client: client.trimmingCharacters(in: .whitespacesAndNewlines),
                project: project.trimmingCharacters(in: .whitespacesAndNewlines),
                workType: workType.trimmingCharacters(in: .whitespacesAndNewlines),
                billable: billable
            )
            try db.clearRunningSession()
        } catch {
            NSLog("Time: could not save entry: \(error)")
        }
        isRunning = false
        isPaused = false
        runningStartedAt = nil
        sessionStartedAt = nil
        heldSeconds = 0
        persistHeld()
        reloadEntries()
        persistForm()
    }

    func addWorkType(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !workTypes.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        do {
            try db.insertWorkType(name: name, sortOrder: workTypes.count)
            reloadWorkTypes()
        } catch {
            NSLog("Time: could not add work type: \(error)")
        }
    }

    func renameWorkType(_ item: WorkTypeItem, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try db.renameWorkType(id: item.id, name: name)
            if workType == item.name {
                workType = name
            }
            reloadWorkTypes()
            persistFormAndRunning()
        } catch {
            NSLog("Time: could not rename work type: \(error)")
        }
    }

    func removeWorkType(_ item: WorkTypeItem) {
        do {
            try db.deleteWorkType(id: item.id)
            if workType == item.name {
                workType = ""
            }
            reloadWorkTypes()
            persistFormAndRunning()
        } catch {
            NSLog("Time: could not remove work type: \(error)")
        }
    }

    func exportCSV(entries: [TimeEntry], to url: URL) throws {
        let body = ReportRollup.csv(from: entries)
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func reload() {
        reloadWorkTypes()
        reloadEntries()
        loadPalette()
        workType = db.setting("work_type") ?? ""
        client = db.setting("client") ?? ""
        project = db.setting("project") ?? ""
        billable = (db.setting("billable") ?? "0") == "1"
    }

    private func reloadWorkTypes() {
        workTypes = db.workTypes()
    }

    private func reloadEntries() {
        entries = db.entries()
    }

    private func restoreSession() {
        guard let row = db.runningSession() else { return }
        runningStartedAt = row.startedAt
        client = row.client
        project = row.project
        workType = row.workType
        billable = row.billable
        isRunning = true
    }

    private func persistForm() {
        do {
            try db.setSetting("work_type", workType)
            try db.setSetting("client", client)
            try db.setSetting("project", project)
            try db.setSetting("billable", billable ? "1" : "0")
        } catch {
            NSLog("Time: could not save settings: \(error)")
        }
    }

    private func persistFormAndRunning() {
        persistForm()
        guard isRunning, let start = runningStartedAt else { return }
        do {
            try db.saveRunningSession(
                startedAt: start,
                client: client,
                project: project,
                workType: workType,
                billable: billable
            )
        } catch {
            NSLog("Time: could not save running session: \(error)")
        }
    }

    func persistHeld() {
        do {
            try db.setSetting("held_seconds", "\(heldSeconds)")
            try db.setSetting("is_paused", isPaused ? "1" : "0")
            if let start = sessionStartedAt {
                try db.setSetting("session_started_at", String(start.timeIntervalSince1970))
            } else {
                try db.setSetting("session_started_at", "")
            }
        } catch {
            NSLog("Time: could not save pause: \(error)")
        }
    }

    private func restoreHeld() {
        heldSeconds = Int(db.setting("held_seconds") ?? "0") ?? 0
        if let raw = db.setting("session_started_at"), let value = Double(raw), value > 0 {
            sessionStartedAt = Date(timeIntervalSince1970: value)
        }
        guard !isRunning, (db.setting("is_paused") ?? "0") == "1" else { return }
        isPaused = true
        runningStartedAt = nil
    }

    func openWorkTypes() {
        onOpenWorkTypes?()
    }

    func openHistory() {
        onOpenHistory?()
    }

    func openWorkTypeMenu() {
        onOpenWorkTypeMenu?()
    }

    func openColors() {
        onOpenColors?()
    }

    func persistPalette() {
        do {
            try db.setSetting("color_font", palette.fontHex)
            try db.setSetting("color_action", palette.actionHex)
            try db.setSetting("color_quiet", palette.quietHex)
            try db.setSetting("color_window", palette.windowHex)
            try db.setSetting("color_minutes", palette.minutesHex)
        } catch {
            NSLog("Time: could not save colors: \(error)")
        }
    }

    private func loadPalette() {
        var next = Palette()
        if let value = db.setting("color_font"), !value.isEmpty { next.fontHex = value }
        if let value = db.setting("color_action"), !value.isEmpty { next.actionHex = value }
        if let value = db.setting("color_quiet"), !value.isEmpty { next.quietHex = value }
        if let value = db.setting("color_window"), !value.isEmpty { next.windowHex = value }
        if let value = db.setting("color_minutes"), !value.isEmpty { next.minutesHex = value }
        palette = next
    }

    func filteredEntries() -> [TimeEntry] {
        entries(in: dateRange, customStart: customStart, customEnd: customEnd)
    }
}
