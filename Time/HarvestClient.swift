import Foundation

struct HarvestPull {
    var clients: [HarvestNamed]
    var projects: [HarvestProject]
    var tasks: [HarvestNamed]
    var assignments: [HarvestAssignment]
}

struct HarvestNamed {
    var id: Int
    var name: String
    var isActive: Bool
}

struct HarvestProject {
    var id: Int
    var name: String
    var isActive: Bool
    var isBillable: Bool
    var clientName: String
    var clientID: Int?
}

struct HarvestAssignment {
    var isActive: Bool
    var billable: Bool
    var projectName: String
    var workType: String
    var projectID: Int
    var taskID: Int
}

enum HarvestAPIError: Error {
    case badURL
    case http
    case decode
}

struct HarvestAPI {
    static let userAgent = "Time (garrett@clarityops.co)"
    private static let host = "api.harvestapp.com"
    private static let root = "https://api.harvestapp.com/v2"

    let accountID: String
    let token: String

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    func pull() async throws -> HarvestPull {
        async let clients = listNamed(path: "/clients?is_active=true", key: "clients")
        async let projects = listProjects()
        async let tasks = listNamed(path: "/tasks?is_active=true", key: "tasks")
        async let assignments = listAssignments()
        return try await HarvestPull(
            clients: clients,
            projects: projects,
            tasks: tasks,
            assignments: assignments
        )
    }

    private func listNamed(path: String, key: String) async throws -> [HarvestNamed] {
        try await pages(path: path, key: key).compactMap { row in
            guard let id = intValue(row["id"]),
                  let name = stringValue(row["name"]), !name.isEmpty else { return nil }
            return HarvestNamed(id: id, name: name, isActive: boolValue(row["is_active"], default: true))
        }
    }

    private func listProjects() async throws -> [HarvestProject] {
        try await pages(path: "/projects?is_active=true", key: "projects").compactMap { row in
            guard let id = intValue(row["id"]),
                  let name = stringValue(row["name"]), !name.isEmpty else { return nil }
            let client = row["client"] as? [String: Any]
            return HarvestProject(
                id: id,
                name: name,
                isActive: boolValue(row["is_active"], default: true),
                isBillable: boolValue(row["is_billable"], default: false),
                clientName: stringValue(client?["name"]) ?? "",
                clientID: intValue(client?["id"])
            )
        }
    }

    private func listAssignments() async throws -> [HarvestAssignment] {
        try await pages(path: "/task_assignments?is_active=true", key: "task_assignments").compactMap { row in
            let project = row["project"] as? [String: Any]
            let task = row["task"] as? [String: Any]
            guard let projectID = intValue(project?["id"]),
                  let taskID = intValue(task?["id"]),
                  let projectName = stringValue(project?["name"]), !projectName.isEmpty,
                  let workType = stringValue(task?["name"]), !workType.isEmpty else { return nil }
            return HarvestAssignment(
                isActive: boolValue(row["is_active"], default: true),
                billable: boolValue(row["billable"], default: false),
                projectName: projectName,
                workType: workType,
                projectID: projectID,
                taskID: taskID
            )
        }
    }

    private func pages(path: String, key: String) async throws -> [[String: Any]] {
        var url = try makeURL(HarvestAPI.root + path)
        var rows: [[String: Any]] = []
        var guardCount = 0
        while guardCount < 40 {
            guardCount += 1
            let object = try await getJSON(url)
            if let items = object[key] as? [[String: Any]] {
                rows.append(contentsOf: items)
            } else {
                throw HarvestAPIError.decode
            }
            guard let links = object["links"] as? [String: Any],
                  let next = links["next"] as? String,
                  !next.isEmpty else { break }
            url = try makeURL(next)
        }
        return rows
    }

    static func decimalHours(seconds: Int) -> Double {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return Double(hours) + Double(minutes) / 60.0
    }

    func createTimeEntry(projectID: Int, taskID: Int, spentDate: String, hours: Double) async throws -> Int {
        try await sendTimeEntry(path: "/time_entries", method: "POST", projectID: projectID, taskID: taskID, spentDate: spentDate, hours: hours)
    }

    func updateTimeEntry(id: Int, projectID: Int, taskID: Int, spentDate: String, hours: Double) async throws -> Int {
        try await sendTimeEntry(path: "/time_entries/\(id)", method: "PATCH", projectID: projectID, taskID: taskID, spentDate: spentDate, hours: hours)
    }

    private func sendTimeEntry(path: String, method: String, projectID: Int, taskID: Int, spentDate: String, hours: Double) async throws -> Int {
        let url = try makeURL(HarvestAPI.root + path)
        let body: [String: Any] = [
            "project_id": projectID,
            "task_id": taskID,
            "spent_date": spentDate,
            "hours": hours,
        ]
        let object = try await requestJSON(url, method: method, body: body)
        guard let id = intValue(object["id"]) else { throw HarvestAPIError.decode }
        return id
    }

    private func getJSON(_ url: URL) async throws -> [String: Any] {
        try await requestJSON(url, method: "GET", body: nil)
    }

    private func requestJSON(_ url: URL, method: String, body: [String: Any]?) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "Harvest-Account-Id")
        request.setValue(HarvestAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HarvestAPIError.http
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarvestAPIError.decode
        }
        return object
    }

    private func makeURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == HarvestAPI.host else {
            throw HarvestAPIError.badURL
        }
        return url
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func boolValue(_ value: Any?, default fallback: Bool) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return fallback
    }
}
