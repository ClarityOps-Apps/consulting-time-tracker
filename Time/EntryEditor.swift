import SwiftUI
import AppKit

struct EntryEditor: View {
    @ObservedObject var store: TimeStore
    var onDone: () -> Void

    private var palette: Palette { store.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.quiet)
                Spacer()
                Button("Done") {
                    if store.saveEditingDraft() {
                        onDone()
                    } else {
                        NSSound.beep()
                    }
                }
                .buttonStyle(SmallActionButtonStyle(color: palette.action))
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                fieldRow("Work type") { workTypeControl }
                fieldRow("Client") { clientControl }
                fieldRow("Project") { projectControl }
                fieldRow("Billable") {
                    LookCheckbox(isOn: billableBinding, palette: palette)
                }
                HStack {
                    Spacer(minLength: 12)
                    DatePicker("", selection: dateBinding, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .frame(minHeight: 32)
                fieldRow("hours") {
                    digitField(hoursBinding)
                }
                fieldRow("minutes") {
                    digitField(minutesBinding)
                }
            }
            .overlay(alignment: .top) {
                palette.line.frame(height: 1)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(palette.window)
        .tint(palette.action)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(palette.font)
            Spacer(minLength: 12)
            content()
        }
        .frame(minHeight: 32)
    }

    private func digitField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .modifier(QuietField(palette: palette))
    }

    private var workTypeControl: some View {
        Button {
            store.openEntryWorkTypeMenu()
        } label: {
            HStack {
                Text(workType.isEmpty ? " " : workType)
                    .foregroundStyle(workType.isEmpty ? palette.quiet : palette.font)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(palette.font)
            }
            .modifier(QuietField(palette: palette))
        }
        .buttonStyle(.plain)
    }

    private var clientControl: some View {
        typedListControl(text: clientBinding, onMenu: { store.openEntryClientMenu() })
    }

    private var projectControl: some View {
        typedListControl(text: projectBinding, onMenu: { store.openEntryProjectMenu() })
    }

    private func typedListControl(text: Binding<String>, onMenu: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            TextField("", text: text)
                .textFieldStyle(.plain)
            Button(action: onMenu) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(palette.font)
                    .frame(width: 12, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .modifier(QuietField(palette: palette))
    }

    private var workType: String { store.editingDraft?.workType ?? "" }

    private var billableBinding: Binding<Bool> {
        draftBinding(\.billable, fallback: false)
    }

    private var dateBinding: Binding<Date> {
        draftBinding(\.date, fallback: Date())
    }

    private var hoursBinding: Binding<String> {
        digitsBinding(\.hoursText)
    }

    private var minutesBinding: Binding<String> {
        digitsBinding(\.minutesText)
    }

    private var clientBinding: Binding<String> {
        draftBinding(\.client, fallback: "")
    }

    private var projectBinding: Binding<String> {
        draftBinding(\.project, fallback: "")
    }

    private func draftBinding<T>(_ keyPath: WritableKeyPath<EntryDraft, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { store.editingDraft?[keyPath: keyPath] ?? fallback },
            set: { value in
                store.updateDraft { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func digitsBinding(_ keyPath: WritableKeyPath<EntryDraft, String>) -> Binding<String> {
        Binding(
            get: { store.editingDraft?[keyPath: keyPath] ?? "" },
            set: { value in
                let digits = value.filter { $0 >= "0" && $0 <= "9" }
                store.updateDraft { $0[keyPath: keyPath] = digits }
            }
        )
    }
}
