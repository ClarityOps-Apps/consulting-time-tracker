import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = TimeStore()
    private var statusItem: NSStatusItem?
    private var timeWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var reportWindow: NSWindow?
    private var editorWindow: NSWindow?
    private var colorsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.onOpenWorkTypes = { [weak self] in
            self?.showWorkTypes()
        }
        store.onOpenColors = { [weak self] in
            self?.showColors()
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
        refreshStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTimeWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusClockImage()
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeft
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
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
    }

    private func refreshWindowColors() {
        let color = store.palette.nsWindow
        timeWindow?.backgroundColor = color
        historyWindow?.backgroundColor = color
        reportWindow?.backgroundColor = color
        editorWindow?.backgroundColor = color
        colorsWindow?.backgroundColor = color
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

    @objc func pickWorkType(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.workType = name
    }

    @objc func showColors() {
        if colorsWindow == nil {
            colorsWindow = makeWindow(
                title: "Colors",
                size: NSSize(width: 280, height: 380),
                root: ColorsView(store: store)
            )
        }
        present(colorsWindow)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        window.center()
        return window
    }
}
