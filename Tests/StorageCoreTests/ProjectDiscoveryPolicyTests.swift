import XCTest
@testable import StorageCore

final class ProjectDiscoveryPolicyTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: FileSystem.canonicalPath(FileManager.default.temporaryDirectory)).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func manifest(_ root: URL, _ path: String) throws -> URL {
        let dir = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("package.json"))
        return dir
    }
    func testCacheManifestsAreNeverClassifiedAsProjects() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for path in [".npm/_npx/tool", ".gradle/caches/module", ".cocoapods/repos/spec", "Library/Caches/CocoaPods/Pods/external", ".pub-cache/hosted/package", ".pnpm-store/dependency", "Library/Android/sdk/templates/project"] {
            let directory = try manifest(root, path)
            XCTAssertNil(ProjectClassifier.detect(directory), path)
        }
        XCTAssertNotNil(ProjectClassifier.detect(try manifest(root, ".hidden/real-app")))
        XCTAssertNotNil(ProjectClassifier.detect(try manifest(root, "projects/gradle-plugin")))
    }
    func testFullAndDirectCacheRootScansSkipCaches() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cached = try manifest(root, ".npm/_npx/tool")
        let project = try manifest(root, "projects/app")
        _ = try manifest(root, "Library/Caches/CocoaPods/sample")
        let report = await Scanner.scan(ScanOptions(roots: [root], includeInventory: false))
        XCTAssertEqual(report.projects.map { $0.root.path }, [project.path])
        let direct = await Scanner.scan(ScanOptions(roots: [cached], includeInventory: false))
        XCTAssertTrue(direct.projects.isEmpty)
        XCTAssertTrue(direct.issues.contains { $0.reason.contains("프로젝트 탐색 제외") })
    }
    func testStoredCacheProjectsRemovedButSharedCacheMeasurementKept() {
        let cached = URL(fileURLWithPath: "/Users/fixture/.npm/_npx/tool")
        let real = URL(fileURLWithPath: "/Users/fixture/Git/app")
        var report = ScanReport()
        report.projects = [Project(root: cached, platforms: [.node], evidence: []), Project(root: real, platforms: [.node], evidence: [])]
        report.artifacts = [
            Artifact(url: cached.appendingPathComponent("node_modules"), owner: "tool", projectID: cached.path, risk: .review, policy: "project-generated", reason: "", measurement: Measurement()),
            Artifact(url: URL(fileURLWithPath: "/Users/fixture/.npm"), owner: "npm", risk: .review, policy: "diagnosis", reason: "", measurement: Measurement())
        ]
        let migrated = CleanupCatalog.upgrade(report)
        XCTAssertEqual(migrated.projects.map(\.root), [real])
        XCTAssertEqual(migrated.artifacts.map(\.owner), ["npm"])
    }
    func testCacheEventsAndCustomCacheRootsAreExcluded() {
        XCTAssertFalse(IncrementalDiscovery.relevant(DirectoryEvent(path: "/Users/fixture/.npm/_npx/tool/package.json", flags: 0), exclusions: []))
        XCTAssertFalse(IncrementalDiscovery.relevant(DirectoryEvent(path: "/Users/fixture/Library/Caches/CocoaPods/sample/package.json", flags: 0), exclusions: []))
        XCTAssertTrue(IncrementalDiscovery.relevant(DirectoryEvent(path: "/Users/fixture/.hidden/project/package.json", flags: 0), exclusions: []))
        XCTAssertTrue(ProjectDiscoveryPolicy.isExcluded(URL(fileURLWithPath: "/custom/gradle/store/project"), environment: ["GRADLE_USER_HOME": "/custom/gradle/store"]))
        XCTAssertFalse(ProjectDiscoveryPolicy.isExcluded(URL(fileURLWithPath: "/custom/gradle/store-other/project"), environment: ["GRADLE_USER_HOME": "/custom/gradle/store"]))
    }
}
