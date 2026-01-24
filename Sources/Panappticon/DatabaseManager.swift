import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private var insertStatement: OpaquePointer?

    private var insertMediaStatement: OpaquePointer?
    private var endMediaStatement: OpaquePointer?

    private init() {
        openDatabase()
        createTable()
        createMediaTable()
        prepareInsertStatement()
        prepareMediaStatements()
    }

    private func errorMessage() -> String {
        if let db = db {
            return String(cString: sqlite3_errmsg(db)!)
        }
        return "unknown error"
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Panappticon")

        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        let dbPath: String = appDir.appendingPathComponent("panappticon.db").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open database: \(errorMessage())")
            return
        }

        // Enable WAL mode
        var pragmaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA journal_mode=WAL;", -1, &pragmaStmt, nil) == SQLITE_OK {
            sqlite3_step(pragmaStmt)
        }
        sqlite3_finalize(pragmaStmt)
    }

    private func createTable() {
        let sql: String = """
            CREATE TABLE IF NOT EXISTS keystrokes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                keystroke TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                application TEXT NOT NULL
            );
            """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("Failed to create table: \(errorMessage())")
            }
        }
        sqlite3_finalize(stmt)
    }

    private func createMediaTable() {
        let sql: String = """
            CREATE TABLE IF NOT EXISTS media_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                artist TEXT NOT NULL DEFAULT '',
                album TEXT NOT NULL DEFAULT '',
                source_app TEXT NOT NULL DEFAULT '',
                started_at TEXT NOT NULL,
                ended_at TEXT
            );
            """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("Failed to create media_history table: \(errorMessage())")
            }
        }
        sqlite3_finalize(stmt)
    }

    private func prepareMediaStatements() {
        let insertSql = "INSERT INTO media_history (title, artist, album, source_app, started_at) VALUES (?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, insertSql, -1, &insertMediaStatement, nil) != SQLITE_OK {
            print("Failed to prepare media insert statement: \(errorMessage())")
        }

        let endSql = "UPDATE media_history SET ended_at = ? WHERE id = ?;"
        if sqlite3_prepare_v2(db, endSql, -1, &endMediaStatement, nil) != SQLITE_OK {
            print("Failed to prepare media end statement: \(errorMessage())")
        }
    }

    private func prepareInsertStatement() {
        let sql: String = "INSERT INTO keystrokes (keystroke, timestamp, application) VALUES (?, ?, ?);"
        if sqlite3_prepare_v2(db, sql, -1, &insertStatement, nil) != SQLITE_OK {
            print("Failed to prepare insert statement: \(errorMessage())")
        }
    }

    func insertKeystroke(keystroke: String, timestamp: String, application: String) {
        guard let stmt = insertStatement else { return }

        sqlite3_reset(stmt)

        _ = keystroke.withCString { ptr in
            sqlite3_bind_text(stmt, 1, ptr, -1, SQLITE_TRANSIENT)
        }
        _ = timestamp.withCString { ptr in
            sqlite3_bind_text(stmt, 2, ptr, -1, SQLITE_TRANSIENT)
        }
        _ = application.withCString { ptr in
            sqlite3_bind_text(stmt, 3, ptr, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Failed to insert keystroke: \(errorMessage())")
        }
    }

    func insertMedia(title: String, artist: String, album: String, sourceApp: String, startedAt: String) -> Int64 {
        guard let stmt = insertMediaStatement else { return -1 }

        sqlite3_reset(stmt)

        _ = title.withCString { ptr in
            sqlite3_bind_text(stmt, 1, ptr, -1, SQLITE_TRANSIENT)
        }
        _ = artist.withCString { ptr in
            sqlite3_bind_text(stmt, 2, ptr, -1, SQLITE_TRANSIENT)
        }
        _ = album.withCString { ptr in
            sqlite3_bind_text(stmt, 3, ptr, -1, SQLITE_TRANSIENT)
        }
        _ = sourceApp.withCString { ptr in
            sqlite3_bind_text(stmt, 4, ptr, -1, SQLITE_TRANSIENT)
        }
        _ = startedAt.withCString { ptr in
            sqlite3_bind_text(stmt, 5, ptr, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Failed to insert media entry: \(errorMessage())")
            return -1
        }

        return sqlite3_last_insert_rowid(db)
    }

    func endMedia(id: Int64, endedAt: String) {
        guard let stmt = endMediaStatement else { return }

        sqlite3_reset(stmt)

        _ = endedAt.withCString { ptr in
            sqlite3_bind_text(stmt, 1, ptr, -1, SQLITE_TRANSIENT)
        }
        sqlite3_bind_int64(stmt, 2, id)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Failed to update media ended_at: \(errorMessage())")
        }
    }

    func close() {
        if let stmt = insertStatement {
            sqlite3_finalize(stmt)
            insertStatement = nil
        }
        if let stmt = insertMediaStatement {
            sqlite3_finalize(stmt)
            insertMediaStatement = nil
        }
        if let stmt = endMediaStatement {
            sqlite3_finalize(stmt)
            endMediaStatement = nil
        }
        if let database = db {
            sqlite3_close(database)
            db = nil
        }
    }
}
