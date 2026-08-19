import SwiftUI

struct TimeWindowView: View {
    @ObservedObject var store: TimeStore
    @State private var bandShown = false
    private var palette: Palette { store.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Time")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.quiet)

            clockFace
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .onAppear { setBand(store.isRunning) }
                .onChange(of: store.isRunning) { _, running in
                    setBand(running)
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

    private var clockFace: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !bandShown && !store.isRunning)) { timeline in
                GeometryReader { geo in
                    let cycle = 5.0
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                    let x = geo.size.width * (-0.18 + 1.36 * phase)
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    palette.action.opacity(0.42),
                                    palette.action.opacity(0.14),
                                    palette.action.opacity(0)
                                ],
                                center: .center,
                                startRadius: 1,
                                endRadius: 38
                            )
                        )
                        .frame(width: 96, height: 46)
                        .position(x: x, y: geo.size.height / 2)
                        .blur(radius: 10)
                        .scaleEffect(bandShown ? 1 : 0.55)
                        .opacity(bandShown ? 1 : 0)
                }
            }
            .allowsHitTesting(false)

            Text(DurationFormat.clock(store.displaySeconds))
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(store.isRunning ? palette.font : palette.quiet)
        }
        .frame(height: 42)
    }

    private func setBand(_ running: Bool) {
        withAnimation(.easeOut(duration: 0.4)) {
            bandShown = running
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
            HStack {
                Text(store.workType.isEmpty ? "Choose…" : store.workType)
                    .foregroundStyle(store.workType.isEmpty ? palette.quiet : palette.font)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("▾")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.quiet)
            }
            .modifier(QuietField(palette: palette))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 148, height: 24)
    }
}
