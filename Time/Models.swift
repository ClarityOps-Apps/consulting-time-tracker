import Foundation

struct TimeEntry: Identifiable, Hashable {
    var id: Int64
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int
    var client: String
    var project: String
    var workType: String
    var billable: Bool

    var metaLine: String {
        var parts = [displayName(client), displayName(project), displayName(workType)]
        if billable {
            parts.append("Billable")
        }
        return parts.joined(separator: " · ")
    }
}

struct WorkTypeItem: Identifiable, Hashable {
    var id: Int64
    var name: String
    var sortOrder: Int
}

struct ClientItem: Identifiable, Hashable {
    var id: Int64
    var name: String
    var sortOrder: Int
    var archived: Bool
}

struct ProjectItem: Identifiable, Hashable {
    var id: Int64
    var name: String
    var sortOrder: Int
    var archived: Bool
}

struct ProjectItem: Identifiable, Hashable {
    var id: Int64
    var name: String
    var sortOrder: Int
    var archived: Bool
}

enum DateRangeKind: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This week"
    case lastWeek = "Last week"
    case thisMonth = "This month"
    case chooseDates = "Choose dates…"

    var id: String { rawValue }

    func bounds(
        now: Date = Date(),
        calendar: Calendar = .current,
        customStart: Date = Date(),
        customEnd: Date = Date()
    ) -> (Date, Date) {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return (start, end)
        case .thisWeek:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
                ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return (start, end)
        case .lastWeek:
            let thisStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
                ?? calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -7, to: thisStart) ?? thisStart
            return (start, thisStart)
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
                ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (start, end)
        case .chooseDates:
            let start = calendar.startOfDay(for: customStart)
            let endDay = calendar.startOfDay(for: customEnd)
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            if start <= end {
                return (start, end)
            }
            return (endDay, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        }
    }
}

struct ClientTotal: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var seconds: Int
}

struct ReportTypeRow: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var seconds: Int
}

struct ReportProjectRow: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var seconds: Int
    var types: [ReportTypeRow]
}

struct ReportClientRow: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var seconds: Int
    var projects: [ReportProjectRow]
}

enum ReportRollup {
    static func clients(from entries: [TimeEntry]) -> [ClientTotal] {
        var totals: [String: Int] = [:]
        var order: [String] = []
        for entry in entries {
            let name = displayName(entry.client)
            if totals[name] == nil {
                order.append(name)
            }
            totals[name, default: 0] += entry.durationSeconds
        }
        return order.map { ClientTotal(name: $0, seconds: totals[$0] ?? 0) }
    }

    static func tree(from entries: [TimeEntry]) -> [ReportClientRow] {
        var clients: [String: [String: [String: Int]]] = [:]
        var clientOrder: [String] = []
        var projectOrder: [String: [String]] = [:]
        var typeOrder: [String: [String]] = [:]

        for entry in entries {
            let client = displayName(entry.client)
            let project = displayName(entry.project)
            let type = displayName(entry.workType)
            if clients[client] == nil {
                clientOrder.append(client)
                clients[client] = [:]
                projectOrder[client] = []
            }
            if clients[client]?[project] == nil {
                projectOrder[client, default: []].append(project)
                clients[client]?[project] = [:]
                typeOrder["\(client)\u{1f}\(project)"] = []
            }
            let typeKey = "\(client)\u{1f}\(project)"
            if clients[client]?[project]?[type] == nil {
                typeOrder[typeKey, default: []].append(type)
            }
            clients[client]?[project]?[type, default: 0] += entry.durationSeconds
        }

        return clientOrder.map { client in
            let projects = (projectOrder[client] ?? []).map { project -> ReportProjectRow in
                let typeKey = "\(client)\u{1f}\(project)"
                let types = (typeOrder[typeKey] ?? []).map { type in
                    ReportTypeRow(name: type, seconds: clients[client]?[project]?[type] ?? 0)
                }
                let seconds = types.reduce(0) { $0 + $1.seconds }
                return ReportProjectRow(name: project, seconds: seconds, types: types)
            }
            let seconds = projects.reduce(0) { $0 + $1.seconds }
            return ReportClientRow(name: client, seconds: seconds, projects: projects)
        }
    }

    static func csv(from entries: [TimeEntry]) -> String {
        var lines = ["client,project,work type,hours and minutes"]
        for client in tree(from: entries) {
            for project in client.projects {
                for type in project.types {
                    let cols = [
                        csvEscape(client.name == "—" ? "" : client.name),
                        csvEscape(project.name == "—" ? "" : project.name),
                        csvEscape(type.name == "—" ? "" : type.name),
                        csvEscape(DurationFormat.entry(type.seconds)),
                    ]
                    lines.append(cols.joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
