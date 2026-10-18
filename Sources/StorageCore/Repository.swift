import Foundation
import CSQLite

public actor SnapshotRepository {
    private let databaseURL: URL
    public init(url: URL) throws {
        databaseURL = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.withDB(url) { db in
            try Self.execute(db, "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, date REAL NOT NULL, kind TEXT NOT NULL, payload BLOB NOT NULL);")
        }
    }
    private static func withDB<T>(_ url: URL, body: (OpaquePointer) throws -> T) throws -> T {
        var pointer: OpaquePointer?
        guard sqlite3_open(url.path, &pointer) == SQLITE_OK, let db = pointer else {
            if let pointer { sqlite3_close(pointer) }; throw RepositoryError.failure("SQLite 열기 실패")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5000)
        return try body(db)
    }
    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw RepositoryError.failure(String(cString: sqlite3_errmsg(db))) }
    }
    public func save<T: Encodable & Sendable>(_ value: T, kind: String, id: String = UUID().uuidString) throws {
        let data = try JSONEncoder().encode(value)
        try Self.withDB(databaseURL) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO events VALUES (?, ?, ?, ?)", -1, &statement, nil) == SQLITE_OK else { throw RepositoryError.failure(String(cString: sqlite3_errmsg(db))) }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, id, -1, transient)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, kind, -1, transient)
            _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), transient) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw RepositoryError.failure(String(cString: sqlite3_errmsg(db))) }
        }
    }
    public func load<T: Decodable & Sendable>(_ type: T.Type, kind: String, limit: Int = 100) throws -> [T] {
        try Self.withDB(databaseURL) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT payload FROM events WHERE kind = ? ORDER BY date DESC LIMIT ?", -1, &statement, nil) == SQLITE_OK else { throw RepositoryError.failure("SQLite 조회 실패") }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, kind, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(statement, 2, Int32(limit))
            var result: [T] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) else { throw RepositoryError.failure("SQLite 행 읽기 실패") }
                result.append(try JSONDecoder().decode(type, from: Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))))
            }
            return result
        }
    }
}
public enum RepositoryError: Error { case failure(String) }
