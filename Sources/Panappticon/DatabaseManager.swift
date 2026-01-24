import Foundation
import SQLCipher

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private var insertStatement: OpaquePointer?
    private var insertMediaStatement: OpaquePointer?
    private var insertScreenshotStatement: OpaquePointer?
    private var password: String?

    private init() {}

    func initialize(password: String) {
        self.password = password

        let dbPath = Self.databasePath()

        if FileManager.default.fileExists(atPath: dbPath) && !isDatabaseEncrypted(atPath: dbPath) {
            migrateUnencryptedDatabase(atPath: dbPath, password: password)
        }

        openDatabase()
        createTable()
        createMediaTable()
        createScreenshotTable()
        prepareInsertStatement()
        prepareMediaStatements()
        prepareScreenshotStatements()
    }

    static func databasePath() -> String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Panappticon")
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("panappticon.db").path
    }

    private func isDatabaseEncrypted(atPath path: String) -> Bool {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return false }
        defer { fileHandle.closeFile() }

        let header = fileHandle.readData(ofLength: 16)
        guard header.count >= 16 else { return false }

        // Unencrypted SQLite files start with "SQLite format 3\0"
        let sqliteHeader = "SQLite format 3\0".data(using: .ascii)!
        return header.prefix(16) != sqliteHeader
    }

    private func migrateUnencryptedDatabase(atPath path: String, password: String) {
        let encryptedPath = path + ".encrypted"
        let backupPath = path + ".unencrypted.bak"

        var plainDb: OpaquePointer?
        guard sqlite3_open(path, &plainDb) == SQLITE_OK else {
            print("Migration: failed to open unencrypted database")
            return
        }

        let attachSql = "ATTACH DATABASE '\(encryptedPath)' AS encrypted KEY '\(password.replacingOccurrences(of: "'", with: "''"))';"
        if sqlite3_exec(plainDb, attachSql, nil, nil, nil) != SQLITE_OK {
            print("Migration: failed to attach encrypted database: \(String(cString: sqlite3_errmsg(plainDb)!))")
            sqlite3_close(plainDb)
            return
        }

        if sqlite3_exec(plainDb, "SELECT sqlcipher_export('encrypted');", nil, nil, nil) != SQLITE_OK {
            print("Migration: failed to export to encrypted database: \(String(cString: sqlite3_errmsg(plainDb)!))")
            sqlite3_exec(plainDb, "DETACH DATABASE encrypted;", nil, nil, nil)
            sqlite3_close(plainDb)
            try? FileManager.default.removeItem(atPath: encryptedPath)
            return
        }

        sqlite3_exec(plainDb, "DETACH DATABASE encrypted;", nil, nil, nil)
        sqlite3_close(plainDb)

        // Clean up WAL/SHM files from old DB
        let walPath = path + "-wal"
        let shmPath = path + "-shm"

        do {
            try FileManager.default.moveItem(atPath: path, toPath: backupPath)
            try FileManager.default.moveItem(atPath: encryptedPath, toPath: path)
            try? FileManager.default.removeItem(atPath: walPath)
            try? FileManager.default.removeItem(atPath: shmPath)
            print("Migration: successfully encrypted database (backup at \(backupPath))")
        } catch {
            print("Migration: failed to swap files: \(error)")
            try? FileManager.default.removeItem(atPath: encryptedPath)
        }
    }

    private func errorMessage() -> String {
        if let db = db {
            return String(cString: sqlite3_errmsg(db)!)
        }
        return "unknown error"
    }

    private func openDatabase() {
        guard let password = self.password else {
            print("No password set")
            return
        }

        let dbPath = Self.databasePath()

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open database: \(errorMessage())")
            return
        }

        // Apply encryption key immediately after opening
        _ = password.withCString { ptr in
            sqlite3_key(db, ptr, Int32(password.utf8.count))
        }

        // Verify the key is correct
        var verifyStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master;", -1, &verifyStmt, nil) != SQLITE_OK {
            print("Database key verification failed: \(errorMessage())")
            sqlite3_close(db)
            db = nil
            return
        }
        if sqlite3_step(verifyStmt) != SQLITE_ROW {
            print("Database key verification failed: \(errorMessage())")
            sqlite3_finalize(verifyStmt)
            sqlite3_close(db)
            db = nil
            return
        }
        sqlite3_finalize(verifyStmt)

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
                timestamp TEXT NOT NULL
            );
            """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("Failed to create media_history table: \(errorMessage())")
            }
        }
        sqlite3_finalize(stmt)

        // Migrate existing databases: drop ended_at, rename started_at -> timestamp
        let migrations = [
            "ALTER TABLE media_history DROP COLUMN ended_at;",
            "ALTER TABLE media_history RENAME COLUMN started_at TO timestamp;"
        ]
        for migration in migrations {
            var migStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, migration, -1, &migStmt, nil) == SQLITE_OK {
                sqlite3_step(migStmt)
            }
            sqlite3_finalize(migStmt)
        }
    }

    private func prepareMediaStatements() {
        let insertSql = "INSERT INTO media_history (title, artist, album, source_app, timestamp) VALUES (?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, insertSql, -1, &insertMediaStatement, nil) != SQLITE_OK {
            print("Failed to prepare media insert statement: \(errorMessage())")
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

    func insertMedia(title: String, artist: String, album: String, sourceApp: String, timestamp: String) {
        guard let stmt = insertMediaStatement else { return }

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
        _ = timestamp.withCString { ptr in
            sqlite3_bind_text(stmt, 5, ptr, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Failed to insert media entry: \(errorMessage())")
        }
    }

    private func createScreenshotTable() {
        let sql: String = """
            CREATE TABLE IF NOT EXISTS screenshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                filename TEXT NOT NULL,
                display_index INTEGER NOT NULL DEFAULT 0,
                active_app TEXT NOT NULL DEFAULT '',
                active_bundle TEXT NOT NULL DEFAULT '',
                timestamp TEXT NOT NULL
            );
            """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("Failed to create screenshots table: \(errorMessage())")
            }
        }
        sqlite3_finalize(stmt)
    }

    private func prepareScreenshotStatements() {
        let sql = "INSERT INTO screenshots (filename, display_index, active_app, active_bundle, timestamp) VALUES (?, ?, ?, ?, ?);"
        if sqlite3_prepare_v2(db, sql, -1, &insertScreenshotStatement, nil) != SQLITE_OK {
            print("Failed to prepare screenshot insert statement: \(errorMessage())")
        }
    }

    func insertScreenshot(filename: String, displayIndex: Int, activeApp: String, activeBundle: String, timestamp: String) {
        guard let stmt = insertScreenshotStatement else { return }

        sqlite3_reset(stmt)

        _ = filename.withCString { ptr in
            sqlite3_bind_text(stmt, 1, ptr, -1, SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(stmt, 2, Int32(displayIndex))
        _ = activeApp.withCString { ptr in
            sqlite3_bind_text(stmt, 3, ptr, -1, SQLITE_TRANSIENT)
        }
        _ = activeBundle.withCString { ptr in
            sqlite3_bind_text(stmt, 4, ptr, -1, SQLITE_TRANSIENT)
        }
        _ = timestamp.withCString { ptr in
            sqlite3_bind_text(stmt, 5, ptr, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Failed to insert screenshot: \(errorMessage())")
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
        if let stmt = insertScreenshotStatement {
            sqlite3_finalize(stmt)
            insertScreenshotStatement = nil
        }
        if let database = db {
            sqlite3_close(database)
            db = nil
        }
    }
}
