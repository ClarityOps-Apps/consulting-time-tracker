import Foundation
import Combine
import SwiftUI

final class TimeStore: ObservableObject {
    @Published var isRunning = false
    @Published var runningStartedAt: Date?
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
            Task { @MainActor in
                self?.now = Date()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    var displaySeconds: Int {
        guard isRunning, let start = runningStartedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
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
        return finished + (isRunning ? displaySeconds : 0)
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
        guard !isRunning else { return }
        runningStartedAt = Date()
        isRunning = true
        persistFormAndRunning()
    }

    func stop() {
        guard isRunning, let start = runningStartedAt else { return }
        let end = Date()
        let seconds = max(0, Int(end.timeIntervalSince(start)))
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
        runningStartedAt = nil
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

    func openWorkTypes() {
        onOpenWorkTypes?()
    }

    func filteredEntries() -> [TimeEntry] {
        entries(in: dateRange, customStart: customStart, customEnd: customEnd)
    }
}
