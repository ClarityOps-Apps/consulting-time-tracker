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
    @Published var clients: [ClientItem] = []
    @Published var projects: [ProjectItem] = []
    @Published var entries: [TimeEntry] = []
    @Published var now = Date()
    @Published var palette = Palette()
    @Published var dateRange: DateRangeKind = .thisWeek
    @Published var customStart = Date()
    @Published var customEnd = Date()
    var onOpenWorkTypes: (() -> Void)?
    var onOpenColors: (() -> Void)?
    var onOpenTime: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onOpenReport: (() -> Void)?
    var onOpenWorkTypeMenu: (() -> Void)?
    var onOpenClientMenu: (() -> Void)?
    var onOpenClients: (() -> Void)?
    var onOpenProjectMenu: (() -> Void)?
    var onOpenProjects: (() -> Void)?
    var onOpenDateRangeMenu: (() -> Void)?

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

    var visibleClients: [ClientItem] {
        clients.filter { !$0.archived }
    }

    var archivedClients: [ClientItem] {
        clients.filter { $0.archived }
    }

    var archivedClientNames: Set<String> {
        Set(archivedClients.map(\.name))
    }

    var visibleProjects: [ProjectItem] {
        projects.filter { !$0.archived }
    }

    var archivedProjects: [ProjectItem] {
        projects.filter { $0.archived }
    }

    var archivedProjectNames: Set<String> {
        Set(archivedProjects.map(\.name))
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
        rememberClient()
        rememberProject()
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
        rememberClient()
        rememberProject()
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
        addNamed(raw, existing: workTypes, insert: db.insertWorkType, reload: reloadWorkTypes, label: "work type")
    }

    func renameWorkType(_ item: WorkTypeItem, to raw: String) {
        renameNamed(item, to: raw, rename: db.renameWorkType, applyCurrent: { name in
            if self.workType == item.name { self.workType = name }
        }, reload: reloadWorkTypes, label: "work type")
    }

    func removeWorkType(_ item: WorkTypeItem) {
        removeNamed(item, delete: db.deleteWorkType, clearCurrent: {
            if self.workType == item.name { self.workType = "" }
        }, reload: reloadWorkTypes, label: "work type")
    }

    func addClient(_ raw: String) {
        addNamed(raw, existing: clients, insert: db.insertClient, reload: reloadClients, label: "client")
    }

    func renameClient(_ item: ClientItem, to raw: String) {
        renameNamed(item, to: raw, rename: db.renameClient, applyCurrent: { name in
            if self.client == item.name { self.client = name }
        }, reload: {
            self.reloadClients()
            self.reloadEntries()
        }, label: "client")
    }

    func removeClient(_ item: ClientItem) {
        removeNamed(item, delete: db.deleteClient, clearCurrent: {
            if self.client == item.name { self.client = "" }
        }, reload: reloadClients, label: "client")
    }

    func archiveClient(_ item: ClientItem) {
        do {
            try db.setArchived(id: item.id, archived: true)
            reloadClients()
            if client == item.name {
                client = ""
                persistFormAndRunning()
            }
        } catch {
            NSLog("Time: could not archive client: \(error)")
        }
    }

    func unhideClient(_ item: ClientItem) {
        do {
            try db.setArchived(id: item.id, archived: false)
            reloadClients()
        } catch {
            NSLog("Time: could not unhide client: \(error)")
        }
    }

    func rememberClient(_ raw: String? = nil) {
        client = resolveTypedName(raw ?? client, items: clients) { name in
            try db.insertClient(name: name, sortOrder: clients.count)
            reloadClients()
        }
    }

    func addProject(_ raw: String) {
        addNamed(raw, existing: projects, insert: db.insertProject, reload: reloadProjects, label: "project")
    }

    func renameProject(_ item: ProjectItem, to raw: String) {
        renameNamed(item, to: raw, rename: db.renameProject, applyCurrent: { name in
            if self.project == item.name { self.project = name }
        }, reload: {
            self.reloadProjects()
            self.reloadEntries()
        }, label: "project")
    }

    func removeProject(_ item: ProjectItem) {
        removeNamed(item, delete: db.deleteProject, clearCurrent: {
            if self.project == item.name { self.project = "" }
        }, reload: reloadProjects, label: "project")
    }

    func archiveProject(_ item: ProjectItem) {
        do {
            try db.setProjectArchived(id: item.id, archived: true)
            reloadProjects()
            if project == item.name {
                project = ""
                persistFormAndRunning()
            }
        } catch {
            NSLog("Time: could not archive project: \(error)")
        }
    }

    func unhideProject(_ item: ProjectItem) {
        do {
            try db.setProjectArchived(id: item.id, archived: false)
            reloadProjects()
        } catch {
            NSLog("Time: could not unhide project: \(error)")
        }
    }

    func rememberProject(_ raw: String? = nil) {
        project = resolveTypedName(raw ?? project, items: projects) { name in
            try db.insertProject(name: name, sortOrder: projects.count)
            reloadProjects()
        }
    }

    private func resolveTypedName(
        _ raw: String,
        items: [NamedListItem],
        insert: (String) throws -> Void
    ) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "" }
        if let match = items.first(where: { !$0.archived && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match.name
        }
        if items.contains(where: { $0.archived && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return ""
        }
        do {
            try insert(name)
        } catch {
            NSLog("Time: could not remember name: \(error)")
        }
        return name
    }

    private func addNamed(
        _ raw: String,
        existing: [NamedListItem],
        insert: (String, Int) throws -> Void,
        reload: () -> Void,
        label: String
    ) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !existing.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        do {
            try insert(name, existing.count)
            reload()
        } catch {
            NSLog("Time: could not add \(label): \(error)")
        }
    }

    private func renameNamed(
        _ item: NamedListItem,
        to raw: String,
        rename: (Int64, String) throws -> Void,
        applyCurrent: (String) -> Void,
        reload: () -> Void,
        label: String
    ) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try rename(item.id, name)
            applyCurrent(name)
            reload()
            persistFormAndRunning()
        } catch {
            NSLog("Time: could not rename \(label): \(error)")
        }
    }

    private func removeNamed(
        _ item: NamedListItem,
        delete: (Int64) throws -> Void,
        clearCurrent: () -> Void,
        reload: () -> Void,
        label: String
    ) {
        do {
            try delete(item.id)
            clearCurrent()
            reload()
            persistFormAndRunning()
        } catch {
            NSLog("Time: could not remove \(label): \(error)")
        }
    }

    func items(for kind: NamedListKind) -> [NamedListItem] {
        switch kind {
        case .workType: return workTypes
        case .client: return clients
        case .project: return projects
        }
    }

    func addItem(_ raw: String, kind: NamedListKind) {
        switch kind {
        case .workType: addWorkType(raw)
        case .client: addClient(raw)
        case .project: addProject(raw)
        }
    }

    func renameItem(_ item: NamedListItem, to raw: String, kind: NamedListKind) {
        switch kind {
        case .workType: renameWorkType(item, to: raw)
        case .client: renameClient(item, to: raw)
        case .project: renameProject(item, to: raw)
        }
    }

    func removeItem(_ item: NamedListItem, kind: NamedListKind) {
        switch kind {
        case .workType: removeWorkType(item)
        case .client: removeClient(item)
        case .project: removeProject(item)
        }
    }

    func exportCSV(entries: [TimeEntry], to url: URL) throws {
        let body = ReportRollup.csv(from: entries)
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func reload() {
        reloadWorkTypes()
        reloadClients()
        reloadProjects()
        reloadEntries()
        loadPalette()
        workType = db.setting("work_type") ?? ""
        client = db.setting("client") ?? ""
        project = db.setting("project") ?? ""
        billable = (db.setting("billable") ?? "0") == "1"
        if archivedClientNames.contains(client) { client = "" }
        if archivedProjectNames.contains(project) { project = "" }
    }

    private func reloadWorkTypes() {
        workTypes = db.workTypes()
    }

    private func reloadClients() {
        clients = db.clients()
    }

    private func reloadProjects() {
        projects = db.projects()
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

    func openTime() {
        onOpenTime?()
    }

    func openHistory() {
        onOpenHistory?()
    }

    func openReport() {
        onOpenReport?()
    }

    func openWorkTypeMenu() {
        onOpenWorkTypeMenu?()
    }

    func openClientMenu() {
        rememberClient()
        onOpenClientMenu?()
    }

    func openClients() {
        onOpenClients?()
    }

    func openProjectMenu() {
        rememberProject()
        onOpenProjectMenu?()
    }

    func openProjects() {
        onOpenProjects?()
    }

    func openDateRangeMenu() {
        onOpenDateRangeMenu?()
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
        let hiddenClients = archivedClientNames
        let hiddenProjects = archivedProjectNames
        return entries(in: dateRange, customStart: customStart, customEnd: customEnd)
            .filter { entry in
                if !entry.client.isEmpty && hiddenClients.contains(entry.client) { return false }
                if !entry.project.isEmpty && hiddenProjects.contains(entry.project) { return false }
                return true
            }
    }
}
