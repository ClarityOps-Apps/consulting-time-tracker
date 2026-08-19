import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ReportView: View {
    @ObservedObject var store: TimeStore
    @State private var range: DateRangeKind = .thisWeek
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var openClients: Set<String> = []
    @State private var openProjects: Set<String> = []

    private var filtered: [TimeEntry] {
        store.entries(in: range, customStart: customStart, customEnd: customEnd)
    }

    private var totalSeconds: Int {
        filtered.reduce(0) { $0 + $1.durationSeconds }
    }

    private var tree: [ReportClientRow] {
        ReportRollup.tree(from: filtered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Report")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.quiet)

            DateRangeBar(
                range: $range,
                customStart: $customStart,
                customEnd: $customEnd,
                trailing: AnyView(
                    Button("Save CSV") { saveCSV() }
                        .buttonStyle(SmallActionButtonStyle())
                )
            )
            .padding(.top, 10)
            .padding(.bottom, 8)

            VStack(spacing: 2) {
                Text(DurationFormat.clock(totalSeconds))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.font)
                Text("Hours and minutes")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.quiet)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tree) { client in
                        clientRow(client)
                    }
                }
                .padding(.top, 6)
                .overlay(alignment: .top) {
                    Theme.line.frame(height: 1)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 400, maxWidth: 400, minHeight: 420)
        .background(Theme.window)
        .onAppear {
            openClients = Set(tree.map(\.id))
            if let first = tree.first, let firstProject = first.projects.first {
                openProjects.insert(projectKey(client: first.id, project: firstProject.id))
            }
        }
    }

    private func clientRow(_ client: ReportClientRow) -> some View {
        let open = openClients.contains(client.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(&openClients, client.id)
            } label: {
                HStack {
                    HStack(spacing: 6) {
                        caret(open)
                        Text(client.name)
                    }
                    Spacer()
                    Text(DurationFormat.clock(client.seconds))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.font)
                .padding(.top, 8)
                .frame(minHeight: 26)
            }
            .buttonStyle(.plain)

            if open {
                ForEach(client.projects) { project in
                    projectRow(client: client.id, project: project)
                }
            }
        }
    }

    private func projectRow(client: String, project: ReportProjectRow) -> some View {
        let key = projectKey(client: client, project: project.id)
        let open = openProjects.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(&openProjects, key)
            } label: {
                HStack {
                    HStack(spacing: 6) {
                        caret(open)
                        Text(project.name)
                    }
                    Spacer()
                    Text(DurationFormat.entry(project.seconds))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.font)
                .padding(.leading, 18)
                .frame(minHeight: 26)
            }
            .buttonStyle(.plain)

            if open {
                ForEach(project.types) { type in
                    HStack {
                        Text(type.name)
                        Spacer()
                        Text(DurationFormat.entry(type.seconds))
                            .monospacedDigit()
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.quiet)
                    .padding(.leading, 48)
                    .frame(minHeight: 24)
                }
            }
        }
    }

    private func caret(_ open: Bool) -> some View {
        Image(systemName: open ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.quiet)
            .frame(width: 12)
    }

    private func projectKey(client: String, project: String) -> String {
        "\(client)\u{1f}\(project)"
    }

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func saveCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Time.csv"
        panel.canCreateDirectories = true
        panel.title = "Save CSV"
        panel.prompt = "Save CSV"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportCSV(entries: filtered, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Time"
            alert.informativeText = "Could not save the CSV."
            alert.runModal()
        }
    }
}
