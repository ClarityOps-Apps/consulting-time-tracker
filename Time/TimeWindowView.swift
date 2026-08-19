import SwiftUI

struct TimeWindowView: View {
    @ObservedObject var store: TimeStore
    @State private var clockPulse = false
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
                .onAppear { kickPulse(store.isRunning) }
                .onChange(of: store.isRunning) { _, running in
                    kickPulse(running)
                }

            Text(store.isRunning ? store.runningSubtitle : " ")
                .font(.system(size: 12))
                .foregroundStyle(palette.quiet)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            Button(store.isRunning ? "Stop" : "Start") {
                store.toggle()
            }
            .buttonStyle(ActionButtonStyle(color: palette.action))
            .padding(.bottom, 14)

            VStack(spacing: 0) {
                fieldRow("Work type") { workTypeControl }
                fieldRow("Client") {
                    TextField("", text: $store.client)
                        .textFieldStyle(.plain)
                        .modifier(QuietField(palette: palette))
                }
                fieldRow("Project") {
                    TextField("", text: $store.project)
                        .textFieldStyle(.plain)
                        .modifier(QuietField(palette: palette))
                }
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

    private var clockLabel: some View {
        let total = max(0, store.displaySeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(hours)")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(store.isRunning ? palette.font : palette.quiet)
            Text("h")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(store.isRunning ? palette.font : palette.quiet)
            Text(String(format: "%02d", minutes))
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(minutesStyle)
                .padding(.leading, 5)
            Text("m")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(store.isRunning ? palette.font : palette.quiet)
        }
        .scaleEffect(store.isRunning && clockPulse ? 1.07 : 1)
        .opacity(store.isRunning && clockPulse ? 0.58 : 1)
        .animation(
            store.isRunning
                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.35),
            value: clockPulse
        )
    }

    private var minutesStyle: some ShapeStyle {
        if store.isRunning {
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color.white, location: 0),
                        .init(color: palette.minutes, location: 0.22),
                        .init(color: palette.minutes, location: 0.40),
                        .init(color: palette.font, location: 0.68),
                        .init(color: palette.font, location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(palette.quiet)
    }

    private func kickPulse(_ running: Bool) {
        clockPulse = false
        guard running else { return }
        DispatchQueue.main.async {
            clockPulse = true
        }
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

    private var workTypeControl: some View {
        Menu {
            ForEach(store.workTypes) { item in
                Button(item.name) {
                    store.workType = item.name
                }
            }
            Divider()
            Button("Edit list…") {
                store.openWorkTypes()
            }
        } label: {
            Text(store.workType.isEmpty ? "Choose…" : store.workType)
                .foregroundStyle(store.workType.isEmpty ? palette.quiet : palette.font)
                .lineLimit(1)
                .modifier(QuietField(palette: palette))
                .overlay(alignment: .trailing) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(palette.font)
                        .padding(.trailing, 8)
                }
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
