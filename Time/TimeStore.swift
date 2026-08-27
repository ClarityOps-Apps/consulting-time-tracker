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
    @Published var parked: [ParkedSession] = []
    @Published var now = Date()
    @Published var breathe = 0.0
    @Published var palette = Palette()
    @Published var harvestConnected = false
    @Published var harvestBusy = false
    @Published var harvestNote = ""
    @Published var harvestAccountID = ""
    @Published var harvestToken = ""
    @Published var dateRange: DateRangeKind = .thisWeek
    @Published var customStart = Date()
    @Published var customEnd = Date()
    @Published var editingDraft: EntryDraft?
    var onOpenWorkTypes: (() -> Void)?
    var onOpenColors: (() -> Void)?
    var onOpenHarvest: (() -> Void)?
    var onOpenTime: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onOpenReport: (() -> Void)?
    var onOpenWorkTypeMenu: (() -> Void)?
    var onOpenClientMenu: (() -> Void)?
    var onOpenClients: (() -> Void)?
    var onOpenProjectMenu: (() -> Void)?
    var onOpenProjects: (() -> Void)?
    var onOpenDateRangeMenu: (() -> Void)?
    var onOpenEntryEditor: (() -> Void)?
    var onCloseEntryEditor: (() -> Void)?
    var onOpenEntryWorkTypeMenu: (() -> Void)?
    var onOpenEntryClientMenu: (() -> Void)?
    var onOpenEntryProjectMenu: (() -> Void)?

    private let db: Database
    private var tickTimer: Timer?
    private var breatheTimer: Timer?
    private var breatheStartedAt: Date?
    private var clockClient = ""
    private var clockProject = ""
    private var clockWorkType = ""
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
        reloadParked()
        reloadHarvestLinks()
        harvestConnected = HarvestKeychain.credentials() != nil
        startTicking()
        if isRunning { startBreathe() }
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

    func startBreathe() {
        breatheStartedAt = Date()
        breatheTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickBreathe()
        }
        RunLoop.main.add(timer, forMode: .common)
        breatheTimer = timer
        tickBreathe()
    }

    func stopBreathe() {
        breatheTimer?.invalidate()
        breatheTimer = nil
        breatheStartedAt = nil
        breathe = 0
    }

    private func tickBreathe() {
        guard isRunning, let origin = breatheStartedAt else {
            breathe = 0
            return
        }
        let elapsed = Date().timeIntervalSince(origin)
        let half = 0.9
        let cycle = half * 2
        let phase = elapsed.truncatingRemainder(dividingBy: cycle)
        let linear = phase <= half ? phase / half : (cycle - phase) / half
        let eased = linear < 0.5 ? 2 * linear * linear : 1 - pow(-2 * linear + 2, 2) / 2
        breathe = eased
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
        Set(archivedClients.map(\.name).filter { !$0.isEmpty })
    }

    var visibleProjects: [ProjectItem] {
        projects.filter { !$0.archived }
    }

    var archivedProjects: [ProjectItem] {
        projects.filter { $0.archived }
    }

    var archivedProjectNames: Set<String> {
        Set(archivedProjects.map(\.name).filter { !$0.isEmpty })
    }

    var todaySeconds: Int {
        let (start, end) = DateRangeKind.today.bounds(now: now)
        let finished = entries
            .filter { $0.startedAt >= start && $0.startedAt < end }
            .reduce(0) { $0 + $1.durationSeconds }
        let active = (isRunning || isPaused) ? displaySeconds : 0
        let other = parked
            .filter { $0.sessionStartedAt >= start && $0.sessionStartedAt < end }
            .reduce(0) { $0 + $1.heldSeconds }
        return finished + active + other
    }

    var currentIdentityKey: String {
        ParkedSession.identityKey(client: client, project: project, workType: workType)
    }

    var otherSessions: [ParkedSession] {
        let clockKey = ParkedSession.identityKey(client: clockClient, project: clockProject, workType: clockWorkType)
        return parked.filter { $0.identityKey != clockKey }
    }

    func resumeParked(_ session: ParkedSession) {
        if isRunning || isPaused {
            if currentIdentityKey == session.identityKey {
                start()
                return
            }
            parkCurrent()
        }
        apply(session)
        do { try db.deleteParkedSession(id: session.id) } catch {
            NSLog("Time: could not drop parked session: \(error)")
        }
        reloadParked()
        start()
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

    func adoptFieldsIfInPlay() {
        rememberClient()
        rememberProject()
        guard isRunning || isPaused else { return }
        let key = currentIdentityKey
        let clockKey = ParkedSession.identityKey(client: clockClient, project: clockProject, workType: clockWorkType)
        guard key != clockKey else { return }
        parkCurrent()
        clockClient = client
        clockProject = project
        clockWorkType = workType
    }

    func start() {
        rememberClient()
        rememberProject()
        let key = currentIdentityKey
        let clockKey = ParkedSession.identityKey(client: clockClient, project: clockProject, workType: clockWorkType)
        let inPlay = isRunning || isPaused
        if inPlay && key == clockKey {
            if isRunning { return }
            now = Date()
            runningStartedAt = now
            isRunning = true
            isPaused = false
            startBreathe()
            persistFormAndRunning()
            persistHeld()
            objectWillChange.send()
            return
        }
        if inPlay {
            parkCurrent()
        }
        if let match = parked.first(where: { $0.identityKey == key }) {
            apply(match)
            do { try db.deleteParkedSession(id: match.id) } catch {
                NSLog("Time: could not drop parked session: \(error)")
            }
            reloadParked()
        } else {
            now = Date()
            sessionStartedAt = now
            heldSeconds = 0
        }
        clockClient = client
        clockProject = project
        clockWorkType = workType
        now = Date()
        runningStartedAt = now
        isRunning = true
        isPaused = false
        startBreathe()
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
        stopBreathe()
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
        stopBreathe()
        persistHeld()
        reloadEntries()
        persistForm()
        reloadParked()
    }

    private func apply(_ session: ParkedSession) {
        client = session.client
        project = session.project
        workType = session.workType
        billable = session.billable
        heldSeconds = session.heldSeconds
        sessionStartedAt = session.sessionStartedAt
        runningStartedAt = nil
        isRunning = false
        isPaused = true
        clockClient = session.client
        clockProject = session.project
        clockWorkType = session.workType
    }

    private func parkCurrent() {
        guard isRunning || isPaused else { return }
        var seconds = heldSeconds
        if isRunning, let start = runningStartedAt {
            seconds += max(0, Int(Date().timeIntervalSince(start)))
        }
        let started = sessionStartedAt ?? runningStartedAt ?? Date()
        let c = (clockClient.isEmpty && clockProject.isEmpty && clockWorkType.isEmpty ? client : clockClient).trimmingCharacters(in: .whitespacesAndNewlines)
        let p = (clockClient.isEmpty && clockProject.isEmpty && clockWorkType.isEmpty ? project : clockProject).trimmingCharacters(in: .whitespacesAndNewlines)
        let w = (clockClient.isEmpty && clockProject.isEmpty && clockWorkType.isEmpty ? workType : clockWorkType).trimmingCharacters(in: .whitespacesAndNewlines)
        let key = ParkedSession.identityKey(client: c, project: p, workType: w)
        do {
            if let existing = parked.first(where: { $0.identityKey == key }) {
                try db.updateParkedSession(
                    id: existing.id,
                    heldSeconds: seconds,
                    sessionStartedAt: started,
                    client: c,
                    project: p,
                    workType: w,
                    billable: billable
                )
            } else {
                try db.insertParkedSession(
                    heldSeconds: seconds,
                    sessionStartedAt: started,
                    client: c,
                    project: p,
                    workType: w,
                    billable: billable
                )
            }
        } catch {
            NSLog("Time: could not park session: \(error)")
        }
        isRunning = false
        isPaused = false
        runningStartedAt = nil
        sessionStartedAt = nil
        heldSeconds = 0
        stopBreathe()
        persistHeld()
        do { try db.clearRunningSession() } catch {
            NSLog("Time: could not clear running session: \(error)")
        }
        reloadParked()
    }

    private func reloadParked() {
        parked = db.parkedSessions()
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
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
        case .client: break
        case .project: break
        }
    }

    func archiveItem(_ item: NamedListItem, kind: NamedListKind) {
        switch kind {
        case .workType: break
        case .client: archiveClient(item)
        case .project: archiveProject(item)
        }
    }

    func unhideItem(_ item: NamedListItem, kind: NamedListKind) {
        switch kind {
        case .workType: break
        case .client: unhideClient(item)
        case .project: unhideProject(item)
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
        reloadParked()
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
        if archivedClientNames.contains(client) { client = "" }
        if archivedProjectNames.contains(project) { project = "" }
        clockClient = client
        clockProject = project
        clockWorkType = workType
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

    func openEntry(_ entry: TimeEntry) {
        editingDraft = EntryDraft.from(entry)
        onOpenEntryEditor?()
    }

    func openNewEntry() {
        editingDraft = EntryDraft.blank(now: now)
        onOpenEntryEditor?()
    }

    func updateDraft(_ mutate: (inout EntryDraft) -> Void) {
        guard var draft = editingDraft else { return }
        mutate(&draft)
        editingDraft = draft
    }

    func openEntryWorkTypeMenu() {
        onOpenEntryWorkTypeMenu?()
    }

    func openEntryClientMenu() {
        snapDraftClient()
        onOpenEntryClientMenu?()
    }

    func openEntryProjectMenu() {
        snapDraftProject()
        onOpenEntryProjectMenu?()
    }

    func saveEditingDraft() -> Bool {
        guard let draft = editingDraft else { return false }
        guard let seconds = draft.durationSeconds() else { return false }
        let client = resolveListName(draft.client, kind: .client)
        let project = resolveListName(draft.project, kind: .project)
        let workType = draft.workType.trimmingCharacters(in: .whitespacesAndNewlines)
        let started = startedDate(for: draft)
        let ended = started.addingTimeInterval(TimeInterval(seconds))
        do {
            if let id = draft.id {
                try db.updateEntry(
                    id: id,
                    startedAt: started,
                    endedAt: ended,
                    durationSeconds: seconds,
                    client: client,
                    project: project,
                    workType: workType,
                    billable: draft.billable
                )
            } else {
                try db.insertEntry(
                    startedAt: started,
                    endedAt: ended,
                    durationSeconds: seconds,
                    client: client,
                    project: project,
                    workType: workType,
                    billable: draft.billable
                )
            }
            reloadEntries()
            reloadClients()
            reloadProjects()
            return true
        } catch {
            NSLog("Time: could not save entry: \(error)")
            return false
        }
    }

    private func startedDate(for draft: EntryDraft) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: draft.date)
        if draft.id == nil {
            return day
        }
        let time = calendar.dateComponents([.hour, .minute, .second], from: draft.startedAt)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
    }

    func resolveListName(_ raw: String, kind: NamedListKind) -> String {
        switch kind {
        case .workType:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .client:
            return resolveTypedName(raw, items: clients) { name in
                try db.insertClient(name: name, sortOrder: clients.count)
                reloadClients()
            }
        case .project:
            return resolveTypedName(raw, items: projects) { name in
                try db.insertProject(name: name, sortOrder: projects.count)
                reloadProjects()
            }
        }
    }

    private func snapDraftClient() {
        updateDraft { draft in
            draft.client = resolveListName(draft.client, kind: .client)
        }
    }

    private func snapDraftProject() {
        updateDraft { draft in
            draft.project = resolveListName(draft.project, kind: .project)
        }
    }

    func openColors() {
        onOpenColors?()
    }

    func openHarvest() {
        onOpenHarvest?()
    }

    func connectHarvest() {
        let accountID = harvestAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = harvestToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty, !token.isEmpty else {
            harvestNote = "Could not connect"
            return
        }
        harvestBusy = true
        harvestNote = ""
        Task { [weak self] in
            await self?.runHarvestPull(accountID: accountID, token: token, connecting: true)
        }
    }

    func pullHarvest() {
        guard let creds = HarvestKeychain.credentials() else {
            harvestConnected = false
            harvestNote = "Could not pull"
            return
        }
        harvestBusy = true
        harvestNote = ""
        Task { [weak self] in
            await self?.runHarvestPull(accountID: creds.accountID, token: creds.token, connecting: false)
        }
    }

    func sendHarvest() {
        guard harvestConnected, let creds = HarvestKeychain.credentials() else { return }
        harvestBusy = true
        harvestNote = ""
        let plan = harvestSendPlan()
        Task { [weak self] in
            await self?.runHarvestSend(accountID: creds.accountID, token: creds.token, plan: plan)
        }
    }

    func disconnectHarvest() {
        HarvestKeychain.clear()
        harvestConnected = false
        harvestBusy = false
        harvestNote = ""
        harvestAccountID = ""
        harvestToken = ""
    }

    func applyHarvestBillableIfLinked() {
        if let value = harvestBillableDefault(project: project, workType: workType) {
            billable = value
        }
    }

    func harvestBillableDefault(project: String, workType: String) -> Bool? {
        let projectName = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeName = workType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectName.isEmpty else { return nil }
        if !typeName.isEmpty, let assigned = harvestAssignments[Self.harvestKey(projectName, typeName)] {
            return assigned
        }
        return harvestProjectsByName[projectName.lowercased()]
    }

    private var harvestProjectsByName: [String: Bool] = [:]
    private var harvestAssignments: [String: Bool] = [:]
    private var harvestProjectIDs: [String: Int] = [:]
    private var harvestTaskIDs: [String: Int] = [:]
    private var harvestAssignmentIDs: [String: (projectID: Int, taskID: Int)] = [:]

    private static func harvestKey(_ project: String, _ workType: String) -> String {
        project.lowercased() + "\u{1e}" + workType.lowercased()
    }

    private func runHarvestPull(accountID: String, token: String, connecting: Bool) async {
        do {
            let pull = try await HarvestAPI(accountID: accountID, token: token).pull()
            if connecting {
                try HarvestKeychain.save(accountID: accountID, token: token)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if connecting {
                    self.harvestConnected = true
                    self.harvestToken = ""
                }
                self.applyHarvestPull(pull)
                self.harvestBusy = false
                self.harvestNote = ""
            }
        } catch {
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.harvestBusy = false
                self.harvestNote = connecting && !self.harvestConnected ? "Could not connect" : "Could not pull"
            }
        }
    }

    private func applyHarvestPull(_ pull: HarvestPull) {
        var projectLinks: [Database.HarvestProjectLink] = []
        var assignmentLinks: [Database.HarvestAssignmentLink] = []
        var seenProjects = Set<String>()
        var seenAssignments = Set<String>()

        for client in pull.clients where client.isActive {
            let local = ensureHarvestName(client.name, kind: .client)
            persistHarvestID(table: "clients", name: local, harvestID: client.id)
        }
        for project in pull.projects where project.isActive {
            let localProject = ensureHarvestName(project.name, kind: .project)
            persistHarvestID(table: "projects", name: localProject, harvestID: project.id)
            let localClient = project.clientName.isEmpty ? "" : ensureHarvestName(project.clientName, kind: .client)
            if !localClient.isEmpty, let clientID = project.clientID {
                persistHarvestID(table: "clients", name: localClient, harvestID: clientID)
            }
            let key = localProject.lowercased()
            if seenProjects.insert(key).inserted {
                projectLinks.append(
                    Database.HarvestProjectLink(
                        projectName: localProject,
                        clientName: localClient,
                        harvestID: project.id,
                        isBillable: project.isBillable
                    )
                )
            }
        }
        for task in pull.tasks where task.isActive {
            let local = ensureHarvestName(task.name, kind: .workType)
            persistHarvestID(table: "work_types", name: local, harvestID: task.id)
        }
        for assignment in pull.assignments where assignment.isActive {
            let localProject = matchHarvestName(assignment.projectName, kind: .project)
            let localType = matchHarvestName(assignment.workType, kind: .workType)
            guard !localProject.isEmpty, !localType.isEmpty else { continue }
            let key = Self.harvestKey(localProject, localType)
            if seenAssignments.insert(key).inserted {
                assignmentLinks.append(
                    Database.HarvestAssignmentLink(
                        projectName: localProject,
                        workType: localType,
                        billable: assignment.billable,
                        harvestProjectID: assignment.projectID,
                        harvestTaskID: assignment.taskID
                    )
                )
            }
        }
        do {
            try db.replaceHarvestLinks(projects: projectLinks, assignments: assignmentLinks)
        } catch {
            NSLog("Time: could not save Harvest names")
            harvestNote = "Could not pull"
        }
        reloadHarvestLinks()
    }

    @discardableResult
    private func ensureHarvestName(_ raw: String, kind: NamedListKind) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }
        let existing = items(for: kind)
        if let match = existing.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if match.archived {
                unhideItem(match, kind: kind)
            }
            return match.name
        }
        addItem(name, kind: kind)
        return name
    }

    private func matchHarvestName(_ raw: String, kind: NamedListKind) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }
        if let match = items(for: kind).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match.name
        }
        return ""
    }

    private func persistHarvestID(table: String, name: String, harvestID: Int) {
        guard !name.isEmpty, harvestID > 0 else { return }
        do {
            try db.setHarvestID(table: table, name: name, harvestID: harvestID)
        } catch {
            NSLog("Time: could not save Harvest id")
        }
    }

    private func reloadHarvestLinks() {
        harvestProjectsByName = [:]
        harvestAssignments = [:]
        harvestProjectIDs = db.harvestIDs(table: "projects")
        harvestTaskIDs = db.harvestIDs(table: "work_types")
        harvestAssignmentIDs = [:]
        for row in db.harvestProjects() {
            harvestProjectsByName[row.projectName.lowercased()] = row.isBillable
            if harvestProjectIDs[row.projectName.lowercased()] == nil {
                harvestProjectIDs[row.projectName.lowercased()] = row.harvestID
            }
        }
        for row in db.harvestAssignments() {
            harvestAssignments[Self.harvestKey(row.projectName, row.workType)] = row.billable
            if row.harvestProjectID > 0, row.harvestTaskID > 0 {
                harvestAssignmentIDs[Self.harvestKey(row.projectName, row.workType)] = (row.harvestProjectID, row.harvestTaskID)
            }
        }
    }

    private struct HarvestSendItem {
        var entryID: Int64
        var harvestTimeEntryId: Int?
        var projectID: Int
        var taskID: Int
        var spentDate: String
        var hours: Double
        var durationSeconds: Int
    }

    private struct HarvestSendPlan {
        var items: [HarvestSendItem]
        var skipped: Int
    }

    private func harvestSendPlan() -> HarvestSendPlan {
        var items: [HarvestSendItem] = []
        var skipped = 0
        for entry in filteredEntries() {
            if harvestSendableMinutes(entry.durationSeconds) == 0 {
                skipped += 1
                continue
            }
            guard let mapped = harvestMapping(for: entry) else {
                skipped += 1
                continue
            }
            let spentDate = harvestSpentDate(entry.startedAt)
            let hours = HarvestAPI.decimalHours(seconds: entry.durationSeconds)
            if entry.harvestTimeEntryId != nil,
               entry.sentDurationSeconds == entry.durationSeconds,
               entry.sentSpentDate == spentDate,
               entry.sentProjectId == mapped.projectID,
               entry.sentTaskId == mapped.taskID {
                skipped += 1
                continue
            }
            items.append(
                HarvestSendItem(
                    entryID: entry.id,
                    harvestTimeEntryId: entry.harvestTimeEntryId,
                    projectID: mapped.projectID,
                    taskID: mapped.taskID,
                    spentDate: spentDate,
                    hours: hours,
                    durationSeconds: entry.durationSeconds
                )
            )
        }
        return HarvestSendPlan(items: items, skipped: skipped)
    }

    private func harvestSendableMinutes(_ seconds: Int) -> Int {
        max(0, seconds) / 60
    }

    private func harvestSpentDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func harvestMapping(for entry: TimeEntry) -> (projectID: Int, taskID: Int)? {
        let projectName = entry.project.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeName = entry.workType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectName.isEmpty, !typeName.isEmpty else { return nil }
        if let assigned = harvestAssignmentIDs[Self.harvestKey(projectName, typeName)] {
            return assigned
        }
        guard let projectID = harvestProjectIDs[projectName.lowercased()], projectID > 0,
              let taskID = harvestTaskIDs[typeName.lowercased()], taskID > 0 else {
            return nil
        }
        return (projectID, taskID)
    }

    private func runHarvestSend(accountID: String, token: String, plan: HarvestSendPlan) async {
        let api = HarvestAPI(accountID: accountID, token: token)
        var sent = 0
        var skipped = plan.skipped
        var transportFailed = false
        for (index, item) in plan.items.enumerated() {
            do {
                let remoteID: Int
                if let existing = item.harvestTimeEntryId {
                    remoteID = try await api.updateTimeEntry(
                        id: existing,
                        projectID: item.projectID,
                        taskID: item.taskID,
                        spentDate: item.spentDate,
                        hours: item.hours
                    )
                } else {
                    remoteID = try await api.createTimeEntry(
                        projectID: item.projectID,
                        taskID: item.taskID,
                        spentDate: item.spentDate,
                        hours: item.hours
                    )
                }
                await MainActor.run { [weak self] in
                    do {
                        try self?.db.markEntrySent(
                            id: item.entryID,
                            harvestTimeEntryId: remoteID,
                            durationSeconds: item.durationSeconds,
                            spentDate: item.spentDate,
                            projectID: item.projectID,
                            taskID: item.taskID
                        )
                    } catch {
                        NSLog("Time: could not mark sent entry")
                    }
                }
                sent += 1
            } catch is HarvestAPIError {
                skipped += 1
            } catch {
                transportFailed = true
                skipped += 1 + (plan.items.count - index - 1)
                break
            }
        }
        let sentCount = sent
        let skippedCount = skipped
        let failed = transportFailed
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.reloadEntries()
            self.harvestBusy = false
            if failed && sentCount == 0 {
                self.harvestNote = "Could not send"
            } else {
                self.harvestNote = "Sent \(sentCount) · skipped \(skippedCount)"
            }
        }
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
