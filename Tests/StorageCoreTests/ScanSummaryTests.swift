import XCTest
@testable import StorageCore

final class ScanSummaryTests: XCTestCase {
    func testLegacyReportSummaryPreservesStatusDateAndCount() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try SnapshotRepository(url: dir.appendingPathComponent("history.sqlite"))
        var report = ScanReport()
        report.startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        report.projects = [Project(root: URL(fileURLWithPath: "/fixture"), platforms: [.node], evidence: [])]
        try await repository.save(report, kind: "scan")
        let summaries = try await repository.scanSummaries()
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.id, report.id)
        XCTAssertEqual(summary.startedAt, report.startedAt)
        XCTAssertEqual(summary.projectCount, 1)
        XCTAssertEqual(summary.isPartial, report.isPartial)
        let empty = try await repository.scanSummaries(limit: 0)
        XCTAssertTrue(empty.isEmpty)
    }
    func testPartialStatusesAndLargeReportSummary() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try SnapshotRepository(url: dir.appendingPathComponent("history.sqlite"))
        var report = ScanReport()
        report.projects = (0..<5000).map { Project(root: URL(fileURLWithPath: "/fixture/\($0)"), platforms: [.node], evidence: ["package.json"]) }
        report.issues = (0..<10000).map { CoverageIssue("/excluded/\($0)", "excluded") }
        try await repository.save(report, kind: "scan")
        var quick = ScanReport(); quick.mode = "빠른 분석"
        try await repository.save(quick, kind: "scan")
        var cancelled = ScanReport(); cancelled.cancelled = true
        try await repository.save(cancelled, kind: "scan")
        let summaries = try await repository.scanSummaries()
        XCTAssertEqual(summaries.count, 3)
        XCTAssertTrue(summaries.allSatisfy(\.isPartial))
        XCTAssertEqual(summaries.first { $0.id == report.id }?.projectCount, 5000)
        let limited = try await repository.scanSummaries(limit: 1)
        XCTAssertEqual(limited.count, 1)
        let original = try await repository.load(ScanReport.self, kind: "scan", limit: 3)
        XCTAssertEqual(original.first { $0.id == report.id }?.issues.count, 10000)
    }
}
