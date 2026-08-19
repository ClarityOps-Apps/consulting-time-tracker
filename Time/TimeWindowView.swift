import SwiftUI

struct TimeWindowView: View {
    @ObservedObject var store: TimeStore
    private var palette: Palette { store.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Time")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.quiet)
                Spacer()
                Button("Colors") {
                    store.openColors()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.quiet)
            }

            clockLabel
                .frame(maxWidth: .infinity, minHeight: 42)
                .padding(.top, 14)

            Text((store.isRunning || store.isPaused) ? store.runningSubtitle : " ")
                .font(.system(size: 12))
                .foregroundStyle(palette.quiet)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            timerButtons
                .padding(.bottom, store.otherSessions.isEmpty ? 14 : 8)

            if !store.otherSessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.otherSessions) { session in
                        Button {
                            store.resumeParked(session)
                        } label: {
                            HStack {
                                Text(session.rowLabel)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.quiet)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 14)
            }

            VStack(spacing: 0) {
                fieldRow("Work type") { workTypeControl }
                fieldRow("Client") { clientControl }
                fieldRow("Project") { projectControl }
                fieldRow("Billable") {
                    LookCheckbox(isOn: $store.billable, palette: palette)
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                palette.line.frame(height: 1)
            }

            HStack(spacing: 8) {
                Text("Today")
                Text(DurationFormat.clock(store.todaySeconds))
                    .monospacedDigit()
                Spacer()
                Button("History") { store.openHistory() }
                    .buttonStyle(.plain)
                Button("Report") { store.openReport() }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 11))
            .foregroundStyle(palette.quiet)
            .padding(.top, 10)
            .overlay(alignment: .top) {
                palette.line.frame(height: 1)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(palette.window)
        .tint(palette.action)
    }

    @ViewBuilder
    private var timerButtons: some View {
        if store.isRunning || store.isPaused {
            HStack(spacing: 8) {
                if store.isPaused {
                    Button("Start") { store.start() }
                        .buttonStyle(ActionButtonStyle(color: palette.action))
                } else {
                    Button("Pause") { store.pause() }
                        .buttonStyle(ActionButtonStyle(color: palette.action))
                }
                Button("Stop") { store.stop() }
                    .buttonStyle(ActionButtonStyle(color: palette.action))
            }
        } else {
            Button("Start") { store.start() }
                .buttonStyle(ActionButtonStyle(color: palette.action))
        }
    }

    private var clockLabel: some View {
        Text(DurationFormat.clock(store.displaySeconds))
            .font(.system(size: 34, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle((store.isRunning || store.isPaused) ? palette.font : palette.quiet)
            .scaleEffect(store.isRunning ? 1 + 0.07 * store.breathe : 1)
            .opacity(store.isRunning ? 1 - 0.42 * store.breathe : 1)
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

    private var clientControl: some View {
        typedListControl(
            text: $store.client,
            onSubmit: { store.adoptFieldsIfInPlay() },
            onMenu: { store.openClientMenu() }
        )
    }

    private var projectControl: some View {
        typedListControl(
            text: $store.project,
            onSubmit: { store.adoptFieldsIfInPlay() },
            onMenu: { store.openProjectMenu() }
        )
    }

    private func typedListControl(
        text: Binding<String>,
        onSubmit: @escaping () -> Void,
        onMenu: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
            Button {
                onMenu()
            } label: {
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

    private var workTypeControl: some View {
        Button {
            store.openWorkTypeMenu()
        } label: {
            HStack {
                Text(store.workType.isEmpty ? "Choose…" : store.workType)
                    .foregroundStyle(store.workType.isEmpty ? palette.quiet : palette.font)
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
}
