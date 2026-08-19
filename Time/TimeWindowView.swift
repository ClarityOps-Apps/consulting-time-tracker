import SwiftUI

struct TimeWindowView: View {
    @ObservedObject var store: TimeStore
    @State private var clockPulse = false
    private var palette: Palette { store.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Time")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.quiet)

            Text(DurationFormat.clock(store.displaySeconds))
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(store.isRunning ? palette.font : palette.quiet)
                .scaleEffect(store.isRunning && clockPulse ? 1.07 : 1)
                .opacity(store.isRunning && clockPulse ? 0.58 : 1)
                .animation(
                    store.isRunning
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.35),
                    value: clockPulse
                )
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
            HStack(spacing: 0) {
                Text(store.workType.isEmpty ? "Choose…" : store.workType)
                    .font(.system(size: 13))
                    .foregroundStyle(store.workType.isEmpty ? palette.quiet : palette.font)
                    .lineLimit(1)
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.quiet)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 16, height: 16)
                .padding(.trailing, 4)
            }
            .frame(width: 148, height: 24)
            .background(palette.wash)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 148, height: 24)
    }
}
