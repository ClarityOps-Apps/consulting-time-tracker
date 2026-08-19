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
        try seedWorkTypesIfNeeded()
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
            try insertWorkType(name: name, sortOrder: index)
        }
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

    func workTypes() -> [WorkTypeItem] {
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, sort_order FROM work_types ORDER BY sort_order, name;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var items: [WorkTypeItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let order = Int(sqlite3_column_int(stmt, 2))
            items.append(WorkTypeItem(id: id, name: name, sortOrder: order))
        }
        return items
    }

    func insertWorkType(name: String, sortOrder: Int) throws {
        let sql = "INSERT INTO work_types(name, sort_order) VALUES(?, ?);"
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

    func renameWorkType(id: Int64, name: String) throws {
        let sql = "UPDATE work_types SET name = ? WHERE id = ?;"
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
    }

    func deleteWorkType(id: Int64) throws {
        let sql = "DELETE FROM work_types WHERE id = ?;"
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
}
