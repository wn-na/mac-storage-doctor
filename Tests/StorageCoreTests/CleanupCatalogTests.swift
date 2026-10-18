import XCTest
@testable import StorageCore

final class CleanupCatalogTests: XCTestCase {
    private func fixture() throws -> URL {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        return URL(fileURLWithPath: FileSystem.canonicalPath(raw))
    }
    func testProjectGeneratedAllowlistKeepWarmAndIdentity() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("let package = Package(name: \"fixture\")".utf8).write(to: root.appendingPathComponent("Package.swift"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
        let project = try XCTUnwrap(ProjectClassifier.detect(root))
        let artifact = try XCTUnwrap(Inventory.candidates(projects: [project], includeShared: false).first)
        XCTAssertTrue(artifact.canTrash); XCTAssertTrue(artifact.quickEligible)
        var legacy = artifact; legacy.policy = "project-diagnosis"
        var report = ScanReport(); report.projects = [project]; report.artifacts = [legacy]
        XCTAssertEqual(CleanupCatalog.upgrade(report).artifacts.first?.policy, "project-generated")
        XCTAssertNoThrow(try CleanupValidator.validate(artifact))
        XCTAssertThrowsError(try CleanupValidator.validate(artifact, keepWarm: [root.path]))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Package.swift"))
        XCTAssertThrowsError(try CleanupValidator.validate(artifact))
    }
    func testNodeDependenciesSelectableButNeverQuickAndPodsNotExecutable() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"dependencies":{"react-native":"1"}}"#.utf8).write(to: root.appendingPathComponent("package.json"))
        for path in ["node_modules", "ios/Pods"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        let project = try XCTUnwrap(ProjectClassifier.detect(root))
        let artifacts = Inventory.candidates(projects: [project], includeShared: false)
        let modules = try XCTUnwrap(artifacts.first { $0.url.lastPathComponent == "node_modules" })
        XCTAssertTrue(modules.canTrash); XCTAssertFalse(modules.quickEligible)
        XCTAssertEqual(modules.kind, .dependencies)
        XCTAssertFalse(try XCTUnwrap(artifacts.first { $0.url.lastPathComponent == "Pods" }).canTrash)
    }
    func testInternalLinksAllowedWithoutFollowingAndExternalLinksBlocked() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("fixture".utf8).write(to: root.appendingPathComponent("target"))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("target"))
        XCTAssertNoThrow(try CleanupValidator.fingerprint(root))
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertThrowsError(try CleanupValidator.fingerprint(root))
    }
    func testTopTenSortsActualMeasuredBytes() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let items = (0..<14).map { value -> Artifact in
            var size = Measurement(); size.allocated = Int64(value * 1024)
            return Artifact(url: root.appendingPathComponent("\(value)"), owner: "fixture", risk: .protected, policy: "diagnosis", reason: "", measurement: size)
        }
        let top = CleanupCatalog.top(items)
        XCTAssertEqual(top.count, 10); XCTAssertEqual(top.first?.measurement.allocated, 13 * 1024)
        XCTAssertEqual(top.last?.measurement.allocated, 4 * 1024)
    }
    func testAnalysisThrottlingAndDailyPersistenceBoundary() {
        let now = Date()
        XCTAssertFalse(AnalysisSchedule.due(last: now.addingTimeInterval(-86399), now: now, intervalHours: 24))
        XCTAssertTrue(AnalysisSchedule.due(last: now.addingTimeInterval(-86400), now: now, intervalHours: 24))
        XCTAssertEqual(AnalysisSchedule.delay(lastIncremental: now, now: now, minutes: 30), 1800)
        XCTAssertEqual(AnalysisSchedule.delay(lastIncremental: now.addingTimeInterval(-7200), now: now, minutes: 30), 30)
    }
}
