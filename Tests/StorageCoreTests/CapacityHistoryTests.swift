import XCTest
@testable import StorageCore

final class CapacityHistoryTests: XCTestCase {
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    private func volume(_ free: Int64, id: String = "disk-a") -> Volume {
        Volume(id: id, url: URL(fileURLWithPath: "/"), name: "Disk", total: 1000, available: free, local: true, removable: false)
    }
    private func point(_ free: Int64, _ time: String, id: String = "disk-a") -> CapacityPoint {
        CapacityPoint(volume: volume(free, id: id), date: date(time))
    }
    func testAggregationPreservesWeightedMeanExtremesAndEndpoints() {
        let raw = [point(100, "2026-01-05T01:00:00Z"), point(400, "2026-01-05T01:01:00Z"), point(700, "2026-01-06T01:00:00Z")]
        let daily = CapacityHistory.aggregate(raw, resolution: .day)
        let result = CapacityHistory.aggregate(daily.reversed(), resolution: .week)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].count, 3)
        XCTAssertEqual(result[0].averageAvailable, 400, accuracy: 0.001)
        XCTAssertEqual(result[0].minimumAvailable, 100)
        XCTAssertEqual(result[0].maximumAvailable, 700)
        XCTAssertEqual(result[0].firstAvailable, 100)
        XCTAssertEqual(result[0].lastAvailable, 700)
    }
    func testWeeksSplitAtMonthBoundaryForAccurateMonthlyRollup() {
        let raw = [point(100, "2026-01-31T23:59:00Z"), point(900, "2026-02-01T00:00:00Z")]
        let weeks = CapacityHistory.aggregate(raw, resolution: .week)
        XCTAssertEqual(weeks.count, 2)
        let months = CapacityHistory.aggregate(weeks, resolution: .month)
        XCTAssertEqual(months.map(\.averageAvailable), [100, 900])
        XCTAssertEqual(months.map(\.bucket), [date("2026-01-01T00:00:00Z"), date("2026-02-01T00:00:00Z")])
    }
    func testRetentionIsIdempotentAndKeepsVolumesSeparate() throws {
        let now = date("2026-10-18T12:00:00Z")
        let points = [point(100, "2026-10-18T11:00:00Z"), point(200, "2026-08-01T00:00:00Z"),
                      point(300, "2025-01-01T00:00:00Z"), point(800, "2025-01-01T00:00:00Z", id: "disk-b")]
        let compact = CapacityHistory.compact(points, now: now)
        XCTAssertEqual(compact.filter { $0.resolution == .minute }.count, 1)
        XCTAssertEqual(compact.filter { $0.resolution == .week }.count, 1)
        XCTAssertEqual(compact.filter { $0.resolution == .month }.count, 2)
        let repeated = CapacityHistory.compact(compact, now: now)
        XCTAssertEqual(Set(compact.map(\.id)), Set(repeated.map(\.id)))
        XCTAssertEqual(repeated.reduce(0) { $0 + $1.count }, 4)
        XCTAssertEqual(repeated.first { $0.volumeID == "disk-b" }?.averageAvailable, 800)
    }
    func testRetentionBoundaryAndGapsDoNotInventSamples() {
        let now = date("2026-10-18T12:00:00Z")
        let boundary = CapacityPoint(volume: volume(200), date: now.addingTimeInterval(-30 * 86400))
        let points = [boundary, point(400, "2026-10-18T12:00:00Z")]
        let compact = CapacityHistory.compact(points, now: now)
        XCTAssertTrue(compact.allSatisfy { $0.resolution == .minute })
        XCTAssertEqual(CapacityHistory.aggregate(compact, resolution: .day).count, 2)
    }
    func testRepositorySurvivesRestartAndDeduplicatesMinute() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let repo = try SnapshotRepository(url: url)
        try await repo.save("existing scan", kind: "scan")
        try await repo.recordCapacity(volume(100), date: date("2026-10-18T12:00:01Z"))
        try await repo.recordCapacity(volume(200), date: date("2026-10-18T12:00:40Z"))
        try await repo.recordCapacity(volume(500, id: "disk-b"), date: date("2026-10-18T12:00:40Z"))
        let restarted = try SnapshotRepository(url: url)
        let points = try await restarted.capacity(volumeID: "disk-a")
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].count, 1)
        XCTAssertEqual(points[0].lastAvailable, 200)
        let existing = try await restarted.load(String.self, kind: "scan")
        XCTAssertEqual(existing, ["existing scan"])
        let none = try await restarted.capacity(volumeID: "disk-a", since: date("2026-10-19T00:00:00Z"))
        XCTAssertTrue(none.isEmpty)
    }
    func testRepositoryCompactionPreservesCountsAcrossRepeatedRuns() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try SnapshotRepository(url: directory.appendingPathComponent("history.sqlite"))
        for (index, time) in ["2025-01-30T12:00:00Z", "2025-01-31T12:00:00Z", "2025-02-01T12:00:00Z", "2026-10-18T12:00:00Z"].enumerated() {
            try await repo.recordCapacity(volume(Int64(index * 100)), date: date(time))
        }
        try await repo.compactCapacity(now: date("2026-10-18T12:00:00Z"))
        try await repo.compactCapacity(now: date("2026-10-18T12:00:00Z"))
        let result = try await repo.capacity(volumeID: "disk-a")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.reduce(0) { $0 + $1.count }, 4)
        XCTAssertEqual(result.first?.averageAvailable, 50)
        XCTAssertEqual(result.first?.minimumAvailable, 0)
        XCTAssertEqual(result.first?.maximumAvailable, 100)
    }
    func testInvalidMeasurementsAreNotStoredAsZero() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try SnapshotRepository(url: directory.appendingPathComponent("history.sqlite"))
        do { try await repo.recordCapacity(volume(-1)); XCTFail("Invalid capacity must fail") } catch {}
        do { try await repo.recordCapacity(volume(1001)); XCTFail("Invalid capacity must fail") } catch {}
        let result = try await repo.capacity(volumeID: "disk-a")
        XCTAssertTrue(result.isEmpty)
    }
}
