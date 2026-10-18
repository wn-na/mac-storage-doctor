import XCTest
@testable import StorageCore

final class CleanupRecordTests: XCTestCase {
    func testLegacyRecordsStillDecode() throws {
        let record = CleanupRecord(path: "/fixture", status: "legacy", before: 100, after: 150)
        let data = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "failureReason"); object.removeValue(forKey: "trashPath")
        let decoded = try JSONDecoder().decode(CleanupRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.observedDelta, 50)
        XCTAssertNil(decoded.failureReason)
        XCTAssertNil(decoded.trashPath)
    }
    func testUnknownAfterIsNotReportedAsZeroChange() throws {
        let record = CleanupRecord(path: "/fixture", status: "moved", before: 100, after: nil, trashPath: "/fixture-trash")
        let decoded = try JSONDecoder().decode(CleanupRecord.self, from: JSONEncoder().encode(record))
        XCTAssertNil(decoded.observedDelta)
        XCTAssertEqual(decoded.trashPath, "/fixture-trash")
    }
    func testFailureIsPersistedWithoutInventingCapacity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try SnapshotRepository(url: directory.appendingPathComponent("history.sqlite"))
        let record = CleanupRecord.failed(path: "/fixture", reason: "Target changed")
        try await repo.save(record, kind: "cleanup", id: record.id.uuidString)
        let saved = try await repo.load(CleanupRecord.self, kind: "cleanup")
        XCTAssertEqual(saved.first?.failureReason, "Target changed")
        XCTAssertNil(saved.first?.observedDelta)
        XCTAssertNil(saved.first?.trashPath)
    }
}
