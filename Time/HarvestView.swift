import AppKit
import SwiftUI

struct HarvestView: View {
    @ObservedObject var store: TimeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Harvest")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.palette.quiet)

            if store.harvestConnected {
                Text("Connected")
                    .font(.system(size: 13))
                    .foregroundStyle(store.palette.font)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                HStack(spacing: 8) {
                    Button("Disconnect") {
                        store.disconnectHarvest()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.palette.quiet)
                    .disabled(store.harvestBusy)
                    Button("Pull") {
                        store.pullHarvest()
                    }
                    .buttonStyle(SmallActionButtonStyle(color: store.palette.action))
                    .disabled(store.harvestBusy)
                    Button("Send") {
                        store.sendHarvest()
                    }
                    .buttonStyle(SmallActionButtonStyle(color: store.palette.action))
                    .disabled(store.harvestBusy)
                }
            } else {
                Text("Token from id.getharvest.com/developers")
                    .font(.system(size: 12))
                    .foregroundStyle(store.palette.quiet)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                labeledField("Account ID", text: $store.harvestAccountID, secure: false)
                    .padding(.bottom, 8)
                labeledField("Personal access token", text: $store.harvestToken, secure: true)
                    .padding(.bottom, 14)
                Button("Connect") {
                    store.connectHarvest()
                }
                .buttonStyle(SmallActionButtonStyle(color: store.palette.action))
                .disabled(store.harvestBusy)
            }

            if !store.harvestNote.isEmpty {
                Text(store.harvestNote)
                    .font(.system(size: 12))
                    .foregroundStyle(store.palette.quiet)
                    .padding(.top, 12)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(store.palette.window)
    }

    private func labeledField(_ name: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(store.palette.font)
            HarvestPasteFieldView(
                text: text,
                masksWhenIdle: secure,
                textColor: NSColor(rgbHex: store.palette.fontHex),
                isEnabled: !store.harvestBusy
            )
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(store.palette.wash)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(store.palette.line, lineWidth: 1)
            )
        }
    }
}

/// AppKit field so Cut/Copy/Paste work without SwiftUI TextField/SecureField.
/// Token stays masked when idle; the clipboard still inserts the real string.
struct HarvestPasteFieldView: NSViewRepresentable {
    @Binding var text: String
    var masksWhenIdle: Bool
    var textColor: NSColor
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> HarvestPasteField {
        let field = HarvestPasteField()
        field.masksWhenIdle = masksWhenIdle
        field.focusRingType = .none
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = isEnabled
        field.isSelectable = true
        field.isEnabled = isEnabled
        field.font = .systemFont(ofSize: 13)
        field.textColor = textColor
        field.allowsEditingTextAttributes = false
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.usesSingleLineMode = true
        field.cell?.sendsActionOnEndEditing = true
        field.delegate = context.coordinator
        field.menu = field.makeEditingMenu()
        field.setRawString(text)
        return field
    }

    func updateNSView(_ field: HarvestPasteField, context: Context) {
        context.coordinator.parent = self
        field.masksWhenIdle = masksWhenIdle
        field.textColor = textColor
        field.isEnabled = isEnabled
        field.isEditable = isEnabled
        field.isSelectable = true
        if !field.isFieldEditing, field.rawString != text {
            field.setRawString(text)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HarvestPasteFieldView

        init(_ parent: HarvestPasteFieldView) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? HarvestPasteField else { return }
            parent.text = field.rawString
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? HarvestPasteField else { return }
            parent.text = field.rawString
        }
    }
}

final class HarvestPasteField: NSTextField, NSMenuItemValidation {
    var masksWhenIdle = false
    private(set) var isFieldEditing = false
    private var raw = ""

    var rawString: String { raw }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 18)
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    func setRawString(_ value: String) {
        raw = value
        refreshDisplay()
    }

    func makeEditingMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action, key) in [
            ("Cut", #selector(cut(_:)), "x"),
            ("Copy", #selector(copy(_:)), "c"),
            ("Paste", #selector(paste(_:)), "v"),
            ("Select All", #selector(selectAll(_:)), "a"),
        ] as [(String, Selector, String)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = .command
            menu.addItem(item)
        }
        return menu
    }

    override func becomeFirstResponder() -> Bool {
        if masksWhenIdle {
            stringValue = raw
        }
        isFieldEditing = true
        return super.becomeFirstResponder()
    }

    override func textDidBeginEditing(_ notification: Notification) {
        isFieldEditing = true
        if stringValue != raw {
            stringValue = raw
        }
        super.textDidBeginEditing(notification)
    }

    override func textDidChange(_ notification: Notification) {
        raw = stringValue
        super.textDidChange(notification)
    }

    override func textDidEndEditing(_ notification: Notification) {
        raw = stringValue
        isFieldEditing = false
        super.textDidEndEditing(notification)
        refreshDisplay()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        NSMenu.popUpContextMenu(makeEditingMenu(), with: event, for: self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEnabled, isKeyTarget else {
            return super.performKeyEquivalent(with: event)
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.option), !mods.contains(.control),
              let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        switch chars {
        case "x":
            cut(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "a":
            selectAll(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        guard isEnabled, let clip = NSPasteboard.general.string(forType: .string) else { return }
        insertPlain(clip)
    }

    @objc func copy(_ sender: Any?) {
        writePasteboard(selectedOrAll())
    }

    @objc func cut(_ sender: Any?) {
        writePasteboard(selectedOrAll())
        replaceSelection(with: "")
    }

    override func selectAll(_ sender: Any?) {
        ensureEditor()
        if let editor = currentEditor() {
            editor.selectedRange = NSRange(location: 0, length: (editor.string as NSString).length)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard isEnabled else { return false }
        switch menuItem.action {
        case #selector(paste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        case #selector(copy(_:)), #selector(cut(_:)):
            return !selectedOrAll().isEmpty
        case #selector(selectAll(_:)):
            return !raw.isEmpty || currentEditor() != nil
        default:
            return true
        }
    }

    private var isKeyTarget: Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder === self || responder === currentEditor()
    }

    private func refreshDisplay() {
        let shown = (masksWhenIdle && !isFieldEditing)
            ? String(repeating: "•", count: raw.count)
            : raw
        if stringValue != shown {
            stringValue = shown
        }
    }

    private func ensureEditor() {
        if currentEditor() == nil {
            window?.makeFirstResponder(self)
        }
    }

    private func selectedOrAll() -> String {
        if let editor = currentEditor() {
            let range = editor.selectedRange
            if range.length > 0 {
                return (editor.string as NSString).substring(with: range)
            }
            return editor.string
        }
        return raw
    }

    private func insertPlain(_ text: String) {
        ensureEditor()
        if let editor = currentEditor() as? NSTextView {
            editor.insertText(text, replacementRange: editor.selectedRange())
            raw = editor.string
            notifyChange()
            return
        }
        raw += text
        stringValue = raw
        notifyChange()
        refreshDisplay()
    }

    private func replaceSelection(with text: String) {
        ensureEditor()
        if let editor = currentEditor() as? NSTextView {
            let range = editor.selectedRange.length > 0
                ? editor.selectedRange
                : NSRange(location: 0, length: (editor.string as NSString).length)
            editor.insertText(text, replacementRange: range)
            raw = editor.string
            notifyChange()
            return
        }
        raw = text
        stringValue = text
        notifyChange()
        refreshDisplay()
    }

    private func writePasteboard(_ value: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(value, forType: .string)
    }

    private func notifyChange() {
        delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: self))
    }
}
