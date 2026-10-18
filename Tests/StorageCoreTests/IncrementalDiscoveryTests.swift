import XCTest
import CoreServices
@testable import StorageCore

final class IncrementalDiscoveryTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: FileSystem.canonicalPath(FileManager.default.temporaryDirectory)).appendingPathComponent("incremental-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    @discardableResult func manifest(_ path: String, content: String = "{}") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    func scan(_ roots: [URL]) async -> ScanReport { await Scanner.scan(ScanOptions(roots: roots, includeInventory: false)) }
    func event(_ url: URL, flags: Int = kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemModified) -> DirectoryEvent { .init(path: url.path, flags: UInt32(flags)) }
    func testCreateAndModifyProjectsMergedWithoutLosingSiblings() async throws {
        try manifest("existing/package.json")
        let original = await scan([root])
        let created = try manifest(".workspace/new/package.json", content: "{\"dependencies\":{\"react-native\":\"1\"}}")
        let plan = IncrementalDiscovery.plan(events: [event(created)], projects: original.projects, watchedRoots: [root], exclusions: [])
        XCTAssertEqual(plan.roots.map(\.path), [created.deletingLastPathComponent().path])
        let merged = IncrementalDiscovery.merge(original, delta: await scan(plan.roots))
        XCTAssertEqual(merged.projects.count, 2)
        XCTAssertTrue(merged.projects.contains { $0.platforms.contains(.reactNative) })
        XCTAssertEqual(merged.mode, "증분 분석")
    }
    func testDeletedManifestRemovesOnlyAffectedProject() async throws {
        let removed = try manifest("gone/package.json")
        try manifest("keep/package.json")
        let original = await scan([root])
        try FileManager.default.removeItem(at: removed)
        let plan = IncrementalDiscovery.plan(events: [event(removed)], projects: original.projects, watchedRoots: [root], exclusions: [])
        let merged = IncrementalDiscovery.merge(original, delta: await scan(plan.roots))
        XCTAssertEqual(merged.projects.map(\.name), ["keep"])
    }
    func testRenamedProjectReconcilesBothPaths() async throws {
        try manifest("old/package.json")
        let original = await scan([root])
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        try FileManager.default.moveItem(at: old, to: new)
        let flags = kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRenamed
        let plan = IncrementalDiscovery.plan(events: [event(old, flags: flags), event(new, flags: flags)], projects: original.projects, watchedRoots: [root], exclusions: [])
        let merged = IncrementalDiscovery.merge(original, delta: await scan(plan.roots))
        XCTAssertEqual(merged.projects.map(\.name), ["new"])
    }
    func testCancelledOrDeniedDeltaPreservesKnownProjects() async throws {
        try manifest("app/package.json")
        let original = await scan([root])
        var delta = ScanReport(); delta.roots = [root]; delta.cancelled = true
        XCTAssertEqual(IncrementalDiscovery.merge(original, delta: delta).projects.count, 1)
        delta.cancelled = false; delta.issues = [.init(root.path, "접근 거부")]
        XCTAssertEqual(IncrementalDiscovery.merge(original, delta: delta).projects.count, 1)
    }
    func testQuickScanPreservesProjectsAndIndexScope() async throws {
        try manifest("app/package.json")
        let original = await scan([root])
        var quick = ScanReport(); quick.mode = "빠른 분석"
        let merged = IncrementalDiscovery.mergeQuick(original, quick: quick)
        XCTAssertEqual(merged.projects.map(\.id), original.projects.map(\.id))
        XCTAssertEqual(merged.roots, original.roots)
        XCTAssertTrue(merged.isPartial)
    }
    func testDroppedEventsAndRootChangesDemandRecovery() {
        for flag in [kFSEventStreamEventFlagUserDropped, kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagRootChanged, kFSEventStreamEventFlagEventIdsWrapped, kFSEventStreamEventFlagUnmount] {
            let plan = IncrementalDiscovery.plan(events: [event(root, flags: flag)], projects: [], watchedRoots: [root], exclusions: [])
            XCTAssertTrue(plan.requiresFullScan)
            XCTAssertTrue(plan.roots.isEmpty)
        }
    }
    func testGeneratedExcludedAndOutOfScopeEventsIgnored() throws {
        let generated = try manifest("app/node_modules/dependency/package.json")
        let excluded = try manifest("excluded/package.json")
        let outside = root.deletingLastPathComponent().appendingPathComponent("package.json")
        let plan = IncrementalDiscovery.plan(events: [event(generated), event(excluded), event(outside)], projects: [], watchedRoots: [root], exclusions: [excluded.deletingLastPathComponent().path])
        XCTAssertTrue(plan.roots.isEmpty)
    }
    func testNestedEventsCoalescedAndNativeOwnerRescanned() async throws {
        try manifest("app/package.json", content: "{\"dependencies\":{\"react-native\":\"1\"}}")
        let gradle = try manifest("app/android/settings.gradle", content: "include ':app'")
        let original = await scan([root])
        let plan = IncrementalDiscovery.plan(events: [event(gradle), event(root.appendingPathComponent("app/package.json"))], projects: original.projects, watchedRoots: [root], exclusions: [])
        XCTAssertEqual(plan.roots.map(\.path), [root.appendingPathComponent("app").path])
    }
    func testExcessiveBatchRequiresFullScan() {
        let plan = IncrementalDiscovery.plan(events: Array(repeating: event(root), count: 1025), projects: [], watchedRoots: [root], exclusions: [])
        XCTAssertTrue(plan.requiresFullScan)
    }
    func testLiveFSEventsDeliversManifestCreation() async throws {
        let target = root.appendingPathComponent("package.json")
        let received = XCTestExpectation(description: "FSEvents manifest event")
        received.assertForOverFulfill = false
        let watcher = await FSEventWatcher()
        try await watcher.start(roots: [root]) { events in
            if events.contains(where: { $0.path == target.path }) { received.fulfill() }
        }
        try Data("{}".utf8).write(to: target)
        await fulfillment(of: [received], timeout: 8)
        await watcher.stop()
    }
}
