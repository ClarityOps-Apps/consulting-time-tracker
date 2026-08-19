import SwiftUI

struct TimeWindowView: View {
    @ObservedObject var store: TimeStore
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Time")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.quiet)

            Text(DurationFormat.clock(store.displaySeconds))
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(store.isRunning ? Theme.font : Theme.quiet)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            Text(store.isRunning ? store.runningSubtitle : " ")
                .font(.system(size: 12))
                .foregroundStyle(Theme.quiet)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            Button(store.isRunning ? "Stop" : "Start") {
                store.toggle()
            }
            .buttonStyle(ActionButtonStyle())
            .padding(.bottom, 14)

            VStack(spacing: 0) {
                fieldRow("Work type") { workTypeControl }
                fieldRow("Client") {
                    TextField("Choose…", text: $store.client)
                        .textFieldStyle(.plain)
                        .modifier(QuietField())
                }
                fieldRow("Project") {
                    TextField("Choose…", text: $store.project)
                        .textFieldStyle(.plain)
                        .modifier(QuietField())
                }
                fieldRow("Billable") {
                    Toggle("", isOn: $store.billable)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .tint(Theme.action)
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Theme.line.frame(height: 1)
            }

            HStack(spacing: 8) {
                Text("Today")
                Text(DurationFormat.clock(store.todaySeconds))
                    .monospacedDigit()
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.quiet)
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Theme.line.frame(height: 1)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(Theme.window)
        .sheet(isPresented: $showEditor) {
            WorkTypeEditor(store: store)
        }
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.font)
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
                showEditor = true
            }
        } label: {
            HStack {
                Text(store.workType.isEmpty ? "Choose…" : store.workType)
                    .foregroundStyle(store.workType.isEmpty ? Theme.quiet : Theme.font)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.quiet)
            }
            .modifier(QuietField())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 148, height: 24)
    }
}
