import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private var insertStatement: OpaquePointer?

    private init() {
        openDatabase()
        createTable()
        prepareInsertStatement()
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

        let dbPath: String = appDir.appendingPathComponent("keystrokes.db").path

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

    func close() {
        if let stmt = insertStatement {
            sqlite3_finalize(stmt)
            insertStatement = nil
        }
        if let database = db {
            sqlite3_close(database)
            db = nil
        }
    }
}
