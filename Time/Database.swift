import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: Error {
    case open(String)
    case exec(String)
}

final class Database {
    private var db: OpaquePointer?

    var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Time", isDirectory: true)
        return dir.appendingPathComponent("time.sqlite")
    }

    init() throws {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            throw DatabaseError.open(lastError())
        }
        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    private func lastError() -> String {
        if let cString = sqlite3_errmsg(db) {
            return String(cString: cString)
        }
        return "unknown"
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? lastError()
            sqlite3_free(err)
            throw DatabaseError.exec(message)
        }
    }

    private func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at INTEGER NOT NULL,
                ended_at INTEGER NOT NULL,
                duration_seconds INTEGER NOT NULL,
                client TEXT NOT NULL DEFAULT '',
                project TEXT NOT NULL DEFAULT '',
                work_type TEXT NOT NULL DEFAULT '',
                billable INTEGER NOT NULL DEFAULT 0
            );
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS work_types (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                sort_order INTEGER NOT NULL
            );
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS running_session (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                started_at INTEGER NOT NULL,
                client TEXT NOT NULL DEFAULT '',
                project TEXT NOT NULL DEFAULT '',
                work_type TEXT NOT NULL DEFAULT '',
                billable INTEGER NOT NULL DEFAULT 0
            );
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """)
        try ensureNameListTable("clients")
        try ensureNameListTable("projects")
        try exec("""
            CREATE TABLE IF NOT EXISTS parked_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                held_seconds INTEGER NOT NULL DEFAULT 0,
                session_started_at INTEGER NOT NULL,
                client TEXT NOT NULL DEFAULT '',
                project TEXT NOT NULL DEFAULT '',
                work_type TEXT NOT NULL DEFAULT '',
                billable INTEGER NOT NULL DEFAULT 0
            );
            """)
        try seedWorkTypesIfNeeded()
        try seedNameListIfNeeded(table: "clients", column: "client")
        try seedNameListIfNeeded(table: "projects", column: "project")
    }

    private func ensureNameListTable(_ table: String) throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS \(table) (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                sort_order INTEGER NOT NULL
            );
            """)
        if !tableHasColumn(table, "archived") {
            try exec("ALTER TABLE \(table) ADD COLUMN archived INTEGER NOT NULL DEFAULT 0;")
        }
    }

    private func tableHasColumn(_ table: String, _ column: String) -> Bool {
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 1), String(cString: cString) == column {
                return true
            }
        }
        return false
    }

    private static let starterWorkTypes = [
        "Research",
        "Meetings",
        "Admin",
        "Project Management",
        "Analysis",
        "Documentation",
        "Client Communication",
        "Business Development",
        "Training",
    ]

    private func seedWorkTypesIfNeeded() throws {
        let count = scalarInt("SELECT COUNT(*) FROM work_types;")
        guard count == 0 else { return }
        for (index, name) in Self.starterWorkTypes.enumerated() {
            try insertListItem(table: "work_types", name: name, sortOrder: index)
        }
    }

    private func seedNameListIfNeeded(table: String, column: String) throws {
        let count = scalarInt("SELECT COUNT(*) FROM \(table);")
        guard count == 0 else { return }
        var names: [String] = []
        var seen = Set<String>()
        let queries = [
            "SELECT DISTINCT TRIM(\(column)) FROM entries WHERE TRIM(\(column)) != '';",
            "SELECT TRIM(\(column)) FROM running_session WHERE id = 1 AND TRIM(\(column)) != '';",
            "SELECT DISTINCT TRIM(\(column)) FROM parked_sessions WHERE TRIM(\(column)) != '';",
        ]
        for sql in queries {
            for raw in stringColumn(sql) {
                if seen.insert(raw).inserted {
                    names.append(raw)
                }
            }
        }
        for (index, name) in names.enumerated() {
            try insertListItem(table: table, name: name, sortOrder: index)
        }
    }

    private func stringColumn(_ sql: String) -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                rows.append(String(cString: cString))
            }
        }
        return rows
    }

    private func scalarInt(_ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    func setting(_ key: String) -> String? {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM settings WHERE key = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) {
            return String(cString: cString)
        }
        return nil
    }

    func setSetting(_ key: String, _ value: String) throws {
        let sql = "INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    func workTypes() -> [WorkTypeItem] { listItems("work_types") }
    func clients() -> [ClientItem] { listItems("clients") }
    func projects() -> [ProjectItem] { listItems("projects") }

    func insertWorkType(name: String, sortOrder: Int) throws {
        try insertListItem(table: "work_types", name: name, sortOrder: sortOrder)
    }

    func renameWorkType(id: Int64, name: String) throws {
        try renameListItem(table: "work_types", id: id, name: name, rewriteColumn: nil)
    }

    func deleteWorkType(id: Int64) throws {
        try deleteListItem(table: "work_types", id: id)
    }

    func insertClient(name: String, sortOrder: Int) throws {
        try insertListItem(table: "clients", name: name, sortOrder: sortOrder)
    }

    func renameClient(id: Int64, name: String) throws {
        try renameListItem(table: "clients", id: id, name: name, rewriteColumn: "client")
    }

    func deleteClient(id: Int64) throws {
        try deleteListItem(table: "clients", id: id)
    }

    func insertProject(name: String, sortOrder: Int) throws {
        try insertListItem(table: "projects", name: name, sortOrder: sortOrder)
    }

    func renameProject(id: Int64, name: String) throws {
        try renameListItem(table: "projects", id: id, name: name, rewriteColumn: "project")
    }

    func deleteProject(id: Int64) throws {
        try deleteListItem(table: "projects", id: id)
    }

    func setArchived(id: Int64, archived: Bool) throws {
        try setListArchived(table: "clients", id: id, archived: archived)
    }

    func setProjectArchived(id: Int64, archived: Bool) throws {
        try setListArchived(table: "projects", id: id, archived: archived)
    }

    private func setListArchived(table: String, id: Int64, archived: Bool) throws {
        let sql = "UPDATE \(table) SET archived = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, archived ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, id)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    private func listItems(_ table: String) -> [NamedListItem] {
        var stmt: OpaquePointer?
        let hasArchived = tableHasColumn(table, "archived")
        let sql = hasArchived
            ? "SELECT id, name, sort_order, archived FROM \(table) ORDER BY sort_order, name;"
            : "SELECT id, name, sort_order FROM \(table) ORDER BY sort_order, name;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var items: [NamedListItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let order = Int(sqlite3_column_int(stmt, 2))
            let archived = hasArchived && sqlite3_column_int(stmt, 3) != 0
            items.append(NamedListItem(id: id, name: name, sortOrder: order, archived: archived))
        }
        return items
    }

    private func insertListItem(table: String, name: String, sortOrder: Int) throws {
        let sql = "INSERT INTO \(table)(name, sort_order) VALUES(?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(sortOrder))
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    private func renameListItem(table: String, id: Int64, name: String, rewriteColumn: String?) throws {
        let old = listItemName(table: table, id: id)
        let sql = "UPDATE \(table) SET name = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, id)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
        if let rewriteColumn, let old, old != name {
            try rewriteText(table: "entries", column: rewriteColumn, from: old, to: name)
            try rewriteText(table: "running_session", column: rewriteColumn, from: old, to: name)
            try rewriteText(table: "parked_sessions", column: rewriteColumn, from: old, to: name)
        }
    }

    private func deleteListItem(table: String, id: Int64) throws {
        let sql = "DELETE FROM \(table) WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    private func listItemName(table: String, id: Int64) -> String? {
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM \(table) WHERE id = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        if sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) {
            return String(cString: cString)
        }
        return nil
    }

    private func rewriteText(table: String, column: String, from old: String, to name: String) throws {
        let sql = "UPDATE \(table) SET \(column) = ? WHERE \(column) = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, old, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    func insertEntry(
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        client: String,
        project: String,
        workType: String,
        billable: Bool
    ) throws {
        let sql = """
            INSERT INTO entries(started_at, ended_at, duration_seconds, client, project, work_type, billable)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(startedAt.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 2, Int64(endedAt.timeIntervalSince1970))
        sqlite3_bind_int(stmt, 3, Int32(durationSeconds))
        sqlite3_bind_text(stmt, 4, client, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, project, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, workType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 7, billable ? 1 : 0)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    func updateEntry(
        id: Int64,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        client: String,
        project: String,
        workType: String,
        billable: Bool
    ) throws {
        let sql = """
            UPDATE entries
            SET started_at = ?, ended_at = ?, duration_seconds = ?, client = ?, project = ?, work_type = ?, billable = ?
            WHERE id = ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(startedAt.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 2, Int64(endedAt.timeIntervalSince1970))
        sqlite3_bind_int(stmt, 3, Int32(durationSeconds))
        sqlite3_bind_text(stmt, 4, client, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, project, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, workType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 7, billable ? 1 : 0)
        sqlite3_bind_int64(stmt, 8, id)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    func entries() -> [TimeEntry] {
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, started_at, ended_at, duration_seconds, client, project, work_type, billable
            FROM entries
            ORDER BY started_at DESC, id DESC;
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var items: [TimeEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            items.append(
                TimeEntry(
                    id: sqlite3_column_int64(stmt, 0),
                    startedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1))),
                    endedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2))),
                    durationSeconds: Int(sqlite3_column_int(stmt, 3)),
                    client: sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "",
                    project: sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "",
                    workType: sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "",
                    billable: sqlite3_column_int(stmt, 7) != 0
                )
            )
        }
        return items
    }

    struct RunningRow {
        var startedAt: Date
        var client: String
        var project: String
        var workType: String
        var billable: Bool
    }

    func runningSession() -> RunningRow? {
        var stmt: OpaquePointer?
        let sql = "SELECT started_at, client, project, work_type, billable FROM running_session WHERE id = 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return RunningRow(
            startedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0))),
            client: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
            project: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "",
            workType: sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "",
            billable: sqlite3_column_int(stmt, 4) != 0
        )
    }

    func saveRunningSession(
        startedAt: Date,
        client: String,
        project: String,
        workType: String,
        billable: Bool
    ) throws {
        let sql = """
            INSERT INTO running_session(id, started_at, client, project, work_type, billable)
            VALUES(1, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                started_at = excluded.started_at,
                client = excluded.client,
                project = excluded.project,
                work_type = excluded.work_type,
                billable = excluded.billable;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(startedAt.timeIntervalSince1970))
        sqlite3_bind_text(stmt, 2, client, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, project, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, workType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, billable ? 1 : 0)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    func clearRunningSession() throws {
        try exec("DELETE FROM running_session;")
    }

    func parkedSessions() -> [ParkedSession] {
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, held_seconds, session_started_at, client, project, work_type, billable
            FROM parked_sessions
            ORDER BY id ASC;
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var items: [ParkedSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            items.append(
                ParkedSession(
                    id: sqlite3_column_int64(stmt, 0),
                    heldSeconds: Int(sqlite3_column_int(stmt, 1)),
                    sessionStartedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2))),
                    client: sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "",
                    project: sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "",
                    workType: sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "",
                    billable: sqlite3_column_int(stmt, 6) != 0
                )
            )
        }
        return items
    }

    @discardableResult
    func insertParkedSession(
        heldSeconds: Int,
        sessionStartedAt: Date,
        client: String,
        project: String,
        workType: String,
        billable: Bool
    ) throws -> Int64 {
        let sql = """
            INSERT INTO parked_sessions(held_seconds, session_started_at, client, project, work_type, billable)
            VALUES(?, ?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(heldSeconds))
        sqlite3_bind_int64(stmt, 2, Int64(sessionStartedAt.timeIntervalSince1970))
        sqlite3_bind_text(stmt, 3, client, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, project, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, workType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 6, billable ? 1 : 0)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
        return sqlite3_last_insert_rowid(db)
    }

    func updateParkedSession(
        id: Int64,
        heldSeconds: Int,
        sessionStartedAt: Date,
        client: String,
        project: String,
        workType: String,
        billable: Bool
    ) throws {
        let sql = """
            UPDATE parked_sessions
            SET held_seconds = ?, session_started_at = ?, client = ?, project = ?, work_type = ?, billable = ?
            WHERE id = ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(heldSeconds))
        sqlite3_bind_int64(stmt, 2, Int64(sessionStartedAt.timeIntervalSince1970))
        sqlite3_bind_text(stmt, 3, client, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, project, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, workType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 6, billable ? 1 : 0)
        sqlite3_bind_int64(stmt, 7, id)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }

    func deleteParkedSession(id: Int64) throws {
        let sql = "DELETE FROM parked_sessions WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.exec(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.exec(lastError())
        }
    }
}
