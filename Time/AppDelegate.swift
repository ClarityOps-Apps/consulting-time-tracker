import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let store = TimeStore()
    private var statusItem: NSStatusItem?
    private var timeWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var reportWindow: NSWindow?
    private var editorWindow: NSWindow?
    private var clientsWindow: NSWindow?
    private var projectsWindow: NSWindow?
    private var colorsWindow: NSWindow?
    private var harvestWindow: NSWindow?
    private var entryEditorWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var revealInFlight = false
    private var lastBreatheRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleReopenEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEReopenApplication)
        )
        store.onOpenWorkTypes = { [weak self] in
            self?.showWorkTypes()
        }
        store.onOpenColors = { [weak self] in
            self?.showColors()
        }
        store.onOpenHarvest = { [weak self] in
            self?.showHarvest()
        }
        store.onOpenTime = { [weak self] in
            self?.showTimeWindow()
        }
        store.onOpenHistory = { [weak self] in
            self?.showHistory()
        }
        store.onOpenReport = { [weak self] in
            self?.showReport()
        }
        store.onOpenWorkTypeMenu = { [weak self] in
            self?.popWorkTypeMenu()
        }
        store.onOpenClientMenu = { [weak self] in
            self?.popClientMenu()
        }
        store.onOpenClients = { [weak self] in
            self?.showClients()
        }
        store.onOpenProjectMenu = { [weak self] in
            self?.popProjectMenu()
        }
        store.onOpenProjects = { [weak self] in
            self?.showProjects()
        }
        store.onOpenDateRangeMenu = { [weak self] in
            self?.popDateRangeMenu()
        }
        store.onOpenEntryEditor = { [weak self] in
            self?.showEntryEditor()
        }
        store.onCloseEntryEditor = { [weak self] in
            self?.closeEntryEditor()
        }
        store.onOpenEntryWorkTypeMenu = { [weak self] in
            self?.popEntryWorkTypeMenu()
        }
        store.onOpenEntryClientMenu = { [weak self] in
            self?.popEntryClientMenu()
        }
        store.onOpenEntryProjectMenu = { [weak self] in
            self?.popEntryProjectMenu()
        }
        buildStatusItem()
        showTimeWindow()
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshStatusItem()
                    self?.refreshWindowColors()
                }
            }
            .store(in: &cancellables)
        store.$now
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)
        store.$breathe
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)
        refreshStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        revealTime()
        return true
    }

    @objc func handleReopenEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        revealTime()
    }

    private func revealTime() {
        if revealInFlight { return }
        revealInFlight = true
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            self?.showTimeWindow()
            NSApp.activate(ignoringOtherApps: true)
            self?.revealInFlight = false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusClockImage()
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(statusItemAction(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if store.isRunning {
            addItem(menu, title: "Pause", action: #selector(pauseTimer))
            addItem(menu, title: "Stop", action: #selector(stopTimer))
        } else if store.isPaused {
            addItem(menu, title: "Start", action: #selector(startTimer))
            addItem(menu, title: "Stop", action: #selector(stopTimer))
        } else {
            addItem(menu, title: "Start", action: #selector(startTimer))
        }
        if !store.otherSessions.isEmpty {
            menu.addItem(.separator())
            for session in store.otherSessions {
                let row = NSMenuItem(title: session.rowLabel, action: #selector(resumeParked(_:)), keyEquivalent: "")
                row.target = self
                row.representedObject = session.id
                menu.addItem(row)
            }
        }
        menu.addItem(.separator())
        addItem(menu, title: "Show window", action: #selector(showTimeWindow))
        addItem(menu, title: "History", action: #selector(showHistory))
        addItem(menu, title: "Report", action: #selector(showReport))
        menu.addItem(.separator())
        addItem(menu, title: "Quit", action: #selector(quit), key: "q")
    }

    private func addItem(_ menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        if button.image == nil {
            button.image = statusClockImage()
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
        }
        if store.isRunning || store.isPaused {
            button.title = " " + DurationFormat.menuBar(store.displaySeconds)
        } else {
            button.title = ""
        }
        button.wantsLayer = true
        if store.isRunning {
            let amount = store.breathe
            button.layer?.opacity = Float(1 - 0.42 * amount)
            let scale = 1 + 0.07 * amount
            button.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        } else {
            button.layer?.opacity = 1
            button.layer?.setAffineTransform(.identity)
        }
    }

    private func refreshWindowColors() {
        let color = store.palette.nsWindow
        timeWindow?.backgroundColor = color
        historyWindow?.backgroundColor = color
        reportWindow?.backgroundColor = color
        editorWindow?.backgroundColor = color
        clientsWindow?.backgroundColor = color
        projectsWindow?.backgroundColor = color
        colorsWindow?.backgroundColor = color
        harvestWindow?.backgroundColor = color
        entryEditorWindow?.backgroundColor = color
    }

    @objc func resumeParked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int64,
              let session = store.otherSessions.first(where: { $0.id == id }) else { return }
        store.resumeParked(session)
        showTimeWindow()
    }

    @objc func startTimer() {
        store.start()
        refreshStatusItem()
    }

    @objc func pauseTimer() {
        store.pause()
        refreshStatusItem()
    }

    @objc func stopTimer() {
        store.stop()
        refreshStatusItem()
    }

    @objc func statusItemAction(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popStatusMenu()
            return
        }
        showTimeWindow()
    }

    private func popStatusMenu() {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        guard let button = statusItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @objc func toggleTimeWindow() {
        if let window = timeWindow, window.isVisible, window.isOnActiveSpace {
            window.orderOut(nil)
            retreatIfNoWindows()
        } else {
            showTimeWindow()
        }
    }

    @objc func showTimeWindow() {
        if timeWindow == nil {
            timeWindow = makeWindow(
                title: "Time",
                size: NSSize(width: 280, height: 400),
                root: TimeWindowView(store: store)
            )
        }
        present(timeWindow)
    }

    @objc func showHistory() {
        if historyWindow == nil {
            historyWindow = makeWindow(
                title: "History",
                size: NSSize(width: 400, height: 560),
                root: HistoryView(store: store)
            )
        }
        present(historyWindow)
    }

    @objc func showReport() {
        if reportWindow == nil {
            reportWindow = makeWindow(
                title: "Report",
                size: NSSize(width: 400, height: 560),
                root: ReportView(store: store)
            )
        }
        present(reportWindow)
    }

    @objc func showWorkTypes() {
        if editorWindow == nil {
            editorWindow = makeWindow(
                title: "Edit list…",
                size: NSSize(width: 320, height: 420),
                root: WorkTypeEditor(store: store) { [weak self] in
                    self?.closeWorkTypes()
                }
            )
        }
        present(editorWindow)
    }

    func closeWorkTypes() {
        editorWindow?.orderOut(nil)
        retreatIfNoWindows()
    }

    @objc func showClients() {
        if clientsWindow == nil {
            clientsWindow = makeWindow(
                title: "Edit list…",
                size: NSSize(width: 320, height: 420),
                root: WorkTypeEditor(store: store, kind: .client) { [weak self] in
                    self?.closeClients()
                }
            )
        }
        present(clientsWindow)
    }

    func closeClients() {
        clientsWindow?.orderOut(nil)
        retreatIfNoWindows()
    }

    @objc func showProjects() {
        if projectsWindow == nil {
            projectsWindow = makeWindow(
                title: "Edit list…",
                size: NSSize(width: 320, height: 420),
                root: WorkTypeEditor(store: store, kind: .project) { [weak self] in
                    self?.closeProjects()
                }
            )
        }
        present(projectsWindow)
    }

    func closeProjects() {
        projectsWindow?.orderOut(nil)
        retreatIfNoWindows()
    }

    @objc func popWorkTypeMenu() {
        let menu = NSMenu()
        for item in store.workTypes {
            let row = NSMenuItem(title: item.name, action: #selector(pickWorkType(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.name
            if item.name == store.workType {
                row.state = .on
            }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit list…", action: #selector(showWorkTypes), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        if let event = NSApp.currentEvent, let view = timeWindow?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else if let view = timeWindow?.contentView {
            let point = NSPoint(x: view.bounds.maxX - 40, y: view.bounds.midY)
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    @objc func popDateRangeMenu() {
        let menu = NSMenu()
        for item in DateRangeKind.allCases {
            let row = NSMenuItem(title: item.rawValue, action: #selector(pickDateRange(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.rawValue
            if item == store.dateRange {
                row.state = .on
            }
            menu.addItem(row)
        }
        if let event = NSApp.currentEvent {
            if let view = historyWindow?.contentView, historyWindow?.isKeyWindow == true {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            } else if let view = reportWindow?.contentView, reportWindow?.isKeyWindow == true {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            } else if let view = NSApp.keyWindow?.contentView {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            }
        }
    }

    @objc func pickDateRange(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = DateRangeKind(rawValue: raw) else { return }
        store.dateRange = kind
    }

    @objc func pickWorkType(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.workType = name
        store.applyHarvestBillableIfLinked()
    }

    @objc func popClientMenu() {
        store.rememberClient()
        let menu = NSMenu()
        for item in store.visibleClients {
            let row = NSMenuItem(title: item.name, action: #selector(pickClient(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.name
            if item.name == store.client {
                row.state = .on
            }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit list…", action: #selector(showClients), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        if let event = NSApp.currentEvent, let view = timeWindow?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else if let view = timeWindow?.contentView {
            let point = NSPoint(x: view.bounds.maxX - 40, y: view.bounds.midY)
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    @objc func pickClient(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.client = name
        store.adoptFieldsIfInPlay()
    }

    @objc func popProjectMenu() {
        store.rememberProject()
        let menu = NSMenu()
        for item in store.visibleProjects {
            let row = NSMenuItem(title: item.name, action: #selector(pickProject(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.name
            if item.name == store.project {
                row.state = .on
            }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit list…", action: #selector(showProjects), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        if let event = NSApp.currentEvent, let view = timeWindow?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else if let view = timeWindow?.contentView {
            let point = NSPoint(x: view.bounds.maxX - 40, y: view.bounds.midY)
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    @objc func pickProject(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.project = name
        store.applyHarvestBillableIfLinked()
        store.adoptFieldsIfInPlay()
    }

    @objc func showEntryEditor() {
        if entryEditorWindow == nil {
            entryEditorWindow = makeWindow(
                title: "Edit",
                size: NSSize(width: 280, height: 360),
                root: EntryEditor(store: store) { [weak self] in
                    self?.closeEntryEditor()
                }
            )
        }
        present(entryEditorWindow)
    }

    func closeEntryEditor() {
        entryEditorWindow?.orderOut(nil)
        store.editingDraft = nil
        retreatIfNoWindows()
    }

    @objc func popEntryWorkTypeMenu() {
        let menu = NSMenu()
        for item in store.workTypes {
            let row = NSMenuItem(title: item.name, action: #selector(pickEntryWorkType(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.name
            if item.name == store.editingDraft?.workType {
                row.state = .on
            }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit list…", action: #selector(showWorkTypes), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        popMenu(menu, in: entryEditorWindow)
    }

    @objc func pickEntryWorkType(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.updateDraft { draft in
            draft.workType = name
            if let value = store.harvestBillableDefault(project: draft.project, workType: name) {
                draft.billable = value
            }
        }
    }

    @objc func popEntryClientMenu() {
        let menu = NSMenu()
        for item in store.visibleClients {
            let row = NSMenuItem(title: item.name, action: #selector(pickEntryClient(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.name
            if item.name == store.editingDraft?.client {
                row.state = .on
            }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit list…", action: #selector(showClients), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        popMenu(menu, in: entryEditorWindow)
    }

    @objc func pickEntryClient(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.updateDraft { $0.client = name }
    }

    @objc func popEntryProjectMenu() {
        let menu = NSMenu()
        for item in store.visibleProjects {
            let row = NSMenuItem(title: item.name, action: #selector(pickEntryProject(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.name
            if item.name == store.editingDraft?.project {
                row.state = .on
            }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit list…", action: #selector(showProjects), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        popMenu(menu, in: entryEditorWindow)
    }

    @objc func pickEntryProject(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.updateDraft { draft in
            draft.project = name
            if let value = store.harvestBillableDefault(project: name, workType: draft.workType) {
                draft.billable = value
            }
        }
    }

    private func popMenu(_ menu: NSMenu, in window: NSWindow?) {
        if let event = NSApp.currentEvent, let view = window?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else if let view = window?.contentView {
            let point = NSPoint(x: view.bounds.maxX - 40, y: view.bounds.midY)
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    @objc func showColors() {
        if colorsWindow == nil {
            colorsWindow = makeWindow(
                title: "Colors",
                size: NSSize(width: 280, height: 340),
                root: ColorsView(store: store)
            )
        }
        present(colorsWindow)
    }

    @objc func showHarvest() {
        if harvestWindow == nil {
            harvestWindow = makeWindow(
                title: "Harvest",
                size: NSSize(width: 280, height: 280),
                root: HarvestView(store: store)
            )
        }
        present(harvestWindow)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.level = .floating
        window.hidesOnDeactivate = false
        placeBelowStatusItem(window)
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func placeBelowStatusItem(_ window: NSWindow) {
        let size = window.frame.size.width > 10
            ? window.frame.size
            : NSSize(width: 280, height: 400)
        var origin = NSPoint.zero
        if let button = statusItem?.button {
            let local = button.convert(button.bounds, to: nil)
            let screenRect = button.window?.convertToScreen(local) ?? local
            origin = NSPoint(
                x: screenRect.midX - size.width / 2,
                y: screenRect.minY - size.height - 10
            )
            if let screen = button.window?.screen ?? NSScreen.main {
                let vf = screen.visibleFrame
                origin.x = min(max(origin.x, vf.minX + 12), vf.maxX - size.width - 12)
                origin.y = min(max(origin.y, vf.minY + 12), vf.maxY - size.height - 12)
            }
        } else if let screen = NSScreen.main {
            origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func retreatIfNoWindows() {
        let anyVisible = [timeWindow, historyWindow, reportWindow, editorWindow, clientsWindow, projectsWindow, colorsWindow, harvestWindow, entryEditorWindow]
            .compactMap { $0 }
            .contains { $0.isVisible }
        if !anyVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func makeWindow<V: View>(title: String, size: NSSize, root: V) -> NSWindow {
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(size)
        window.backgroundColor = store.palette.nsWindow
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.delegate = self
        window.standardWindowButton(.closeButton)?.isEnabled = true
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.center()
        return window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === entryEditorWindow {
            store.editingDraft = nil
        }
        sender.orderOut(nil)
        retreatIfNoWindows()
        return false
    }

    func windowWillMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.orderOut(nil)
        retreatIfNoWindows()
    }
}
