import Foundation
import CSQLite

public actor SnapshotRepository {
    private let databaseURL: URL
    private var capacityMaintenanceDate: Date?
    public init(url: URL) throws {
        databaseURL = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.withDB(url) { db in
            try Self.execute(db, "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, date REAL NOT NULL, kind TEXT NOT NULL, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS capacity (id TEXT PRIMARY KEY, volume TEXT NOT NULL, resolution TEXT NOT NULL, date REAL NOT NULL, payload BLOB NOT NULL); CREATE INDEX IF NOT EXISTS capacity_volume_date ON capacity(volume, date); CREATE INDEX IF NOT EXISTS events_kind_date ON events(kind, date DESC);")
        }
    }
    /// Replace a repeated observation in the same minute, rather than overweighting manual refreshes.
    public func recordCapacity(_ volume: Volume, date: Date = Date()) throws {
        guard volume.total > 0, volume.available >= 0, volume.available <= volume.total else {
            throw RepositoryError.failure("유효하지 않은 볼륨 용량입니다.")
        }
        try Self.withDB(databaseURL) { db in try Self.insertCapacity(CapacityPoint(volume: volume, date: date), db: db) }
        if capacityMaintenanceDate.map({ date.timeIntervalSince($0) >= 86400 || date < $0 }) ?? true {
            try compactCapacity(now: date)
            capacityMaintenanceDate = date
        }
    }
    public func capacity(volumeID: String, since: Date = .distantPast) throws -> [CapacityPoint] {
        try Self.withDB(databaseURL) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT payload FROM capacity WHERE volume = ? AND date >= ? ORDER BY date", -1, &statement, nil) == SQLITE_OK else { throw RepositoryError.failure("용량 이력 조회 실패") }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, volumeID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 2, since.timeIntervalSince1970)
            return try Self.capacityRows(statement)
        }
    }
    public func compactCapacity(now: Date = Date()) throws {
        try Self.withDB(databaseURL) { db in
            try Self.execute(db, "BEGIN IMMEDIATE")
            do {
                // Only rewrite expired detail and aggregates. Current minute records stay untouched.
                let cutoff = now.addingTimeInterval(-30 * 86400).timeIntervalSince1970
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT payload FROM capacity WHERE resolution != 'minute' OR date < ?", -1, &statement, nil) == SQLITE_OK else { throw RepositoryError.failure("용량 이력 압축 조회 실패") }
                sqlite3_bind_double(statement, 1, cutoff)
                let points: [CapacityPoint]
                do { points = try Self.capacityRows(statement) }
                catch { sqlite3_finalize(statement); throw error }
                sqlite3_finalize(statement)
                statement = nil
                guard sqlite3_prepare_v2(db, "DELETE FROM capacity WHERE resolution != 'minute' OR date < ?", -1, &statement, nil) == SQLITE_OK else { throw RepositoryError.failure("용량 이력 압축 실패") }
                sqlite3_bind_double(statement, 1, cutoff)
                let status = sqlite3_step(statement)
                sqlite3_finalize(statement)
                guard status == SQLITE_DONE else { throw RepositoryError.failure("용량 이력 압축 실패") }
                for point in CapacityHistory.compact(points, now: now) { try Self.insertCapacity(point, db: db) }
                try Self.execute(db, "COMMIT")
            } catch {
                try? Self.execute(db, "ROLLBACK")
                throw error
            }
        }
    }
    private static func capacityRows(_ statement: OpaquePointer?) throws -> [CapacityPoint] {
        var points: [CapacityPoint] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return points }
            guard status == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) else { throw RepositoryError.failure("용량 이력 읽기 실패") }
            points.append(try JSONDecoder().decode(CapacityPoint.self, from: Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))))
        }
    }
    private static func insertCapacity(_ point: CapacityPoint, db: OpaquePointer) throws {
        let data = try JSONEncoder().encode(point)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO capacity VALUES (?, ?, ?, ?, ?)", -1, &statement, nil) == SQLITE_OK else { throw RepositoryError.failure("용량 이력 저장 실패") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, point.id, -1, transient)
        sqlite3_bind_text(statement, 2, point.volumeID, -1, transient)
        sqlite3_bind_text(statement, 3, point.resolution.rawValue, -1, transient)
        sqlite3_bind_double(statement, 4, point.lastDate.timeIntervalSince1970)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32($0.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw RepositoryError.failure("용량 이력 저장 실패") }
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
    public func scanSummaries(limit: Int = 30) throws -> [ScanSummary] {
        try Self.withDB(databaseURL) { db in
            let sql = """
            WITH latest AS (SELECT CAST(payload AS TEXT) AS report FROM events WHERE kind = 'scan' ORDER BY date DESC LIMIT ?)
            SELECT json_extract(report, '$.id'), json_extract(report, '$.startedAt'),
                   json_extract(report, '$.mode'), json_array_length(report, '$.projects'),
                   json_extract(report, '$.cancelled'), json_array_length(report, '$.issues') FROM latest
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw RepositoryError.failure("검사 요약 조회 실패") }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(clamping: max(0, limit)))
            var result: [ScanSummary] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { return result }
                guard status == SQLITE_ROW, let idText = sqlite3_column_text(statement, 0),
                      let id = UUID(uuidString: String(cString: idText)), let modeText = sqlite3_column_text(statement, 2) else {
                    throw RepositoryError.failure("검사 요약 읽기 실패")
                }
                let mode = String(cString: modeText)
                result.append(ScanSummary(id: id, startedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
                                          mode: mode, projectCount: Int(sqlite3_column_int64(statement, 3)),
                                          isPartial: sqlite3_column_int(statement, 4) != 0 || sqlite3_column_int(statement, 5) != 0 || mode != "전체 분석"))
            }
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
public enum RepositoryError: LocalizedError {
    case failure(String)
    public var errorDescription: String? { if case .failure(let reason) = self { return reason }; return nil }
}
