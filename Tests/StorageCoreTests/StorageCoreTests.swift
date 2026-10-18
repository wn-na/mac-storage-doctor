import XCTest
@testable import StorageCore

final class StorageCoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: FileSystem.canonicalPath(FileManager.default.temporaryDirectory)).appendingPathComponent("storage-doctor-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ relative: String, _ content: String = "test") throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    func testPureDartIsNotFlutter() throws {
        try file("dart/pubspec.yaml", "name: dart\ndependencies:\n  http: any\n")
        XCTAssertNil(ProjectClassifier.detect(root.appendingPathComponent("dart")))
    }
    func testFlutterDependencyAndNativeGrouping() throws {
        try file("app/pubspec.yaml", "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try file("app/android/settings.gradle", "include ':app'")
        try file("app/android/gradlew")
        try file("app/ios/App.xcodeproj/project.pbxproj")
        let app = try XCTUnwrap(ProjectClassifier.detect(root.appendingPathComponent("app")))
        let android = try XCTUnwrap(ProjectClassifier.detect(root.appendingPathComponent("app/android")))
        let ios = try XCTUnwrap(ProjectClassifier.detect(root.appendingPathComponent("app/ios")))
        XCTAssertEqual(app.platforms, [.flutter, .android, .apple])
        XCTAssertEqual(ProjectClassifier.group([app, android, ios]).count, 1)
    }
    func testReactNativeContentAndWorkspace() throws {
        try file("repo/package.json", "{\"workspaces\":[\"apps/*\"]}")
        try file("repo/apps/mobile/package.json", "{\"dependencies\":{\"react-native\":\"1\",\"expo\":\"1\"}}")
        let parent = try XCTUnwrap(ProjectClassifier.detect(root.appendingPathComponent("repo")))
        let child = try XCTUnwrap(ProjectClassifier.detect(root.appendingPathComponent("repo/apps/mobile")))
        let grouped = ProjectClassifier.group([child, parent])
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[1].workspace, parent.id)
        XCTAssertEqual(child.platforms, [.reactNative, .expo])
    }
    func testOrdinaryBuildFolderNotCandidate() throws {
        try file("random/build/source.swift")
        XCTAssertNil(ProjectClassifier.detect(root.appendingPathComponent("random")))
        XCTAssertTrue(Inventory.candidates(projects: [], includeShared: false).isEmpty)
    }
    func testHiddenProjectOutsideGitDiscovered() async throws {
        try file("Documents/.workspace/mobile/package.json", "{\"dependencies\":{\"react-native\":\"1\"}}")
        let report = await Scanner.scan(ScanOptions(roots: [root], includeInventory: false))
        XCTAssertEqual(report.projects.count, 1)
        XCTAssertTrue(report.projects[0].root.path.contains(".workspace"))
    }
    func testExcludedAndSymlinkProjectsNotScanned() async throws {
        try file("excluded/app/package.json", "{}")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("excluded"))
        let report = await Scanner.scan(ScanOptions(roots: [root], exclusions: [root.appendingPathComponent("excluded").path], includeInventory: false))
        XCTAssertTrue(report.projects.isEmpty, "root=\(root.path) projects=\(report.projects.map(\.id)) issues=\(report.issues)")
        XCTAssertTrue(report.isPartial)
    }
    func testMissingRootReportsPartial() async {
        let report = await Scanner.scan(ScanOptions(roots: [root.appendingPathComponent("gone")], includeInventory: false))
        XCTAssertTrue(report.isPartial)
        XCTAssertFalse(report.issues.isEmpty)
    }
    func testHardLinksCountOnceAndSymlinksNotFollowed() throws {
        let original = try file("data/file", String(repeating: "x", count: 8192))
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("data/hardlink"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("data/loop"), withDestinationURL: root)
        let result = FileSystem.measure(root.appendingPathComponent("data"))
        XCTAssertEqual(result.logical, 8192)
        XCTAssertEqual(result.files, 1)
    }
    func testProtectedArtifactCannotBeExecuted() throws {
        let url = try file("protected/data")
        let item = Artifact(url: url, owner: "user", risk: .protected, policy: "diagnosis", reason: "", measurement: Measurement(), identity: try FileSystem.identity(url))
        XCTAssertThrowsError(try CleanupValidator.validate(item, home: root))
    }
    func makeDerived() throws -> Artifact {
        let dir = root.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-123")
        let info: [String: String] = ["WorkspacePath": root.appendingPathComponent("project/App.xcodeproj").path]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("info.plist"))
        return Artifact(url: dir, owner: "Xcode", risk: .review, policy: "xcode-derived-child", reason: "", measurement: FileSystem.measure(dir), identity: try FileSystem.identity(dir))
    }
    func testDerivedAllowlistAndKeepWarm() throws {
        let artifact = try makeDerived()
        XCTAssertNoThrow(try CleanupValidator.validate(artifact, home: root))
        XCTAssertThrowsError(try CleanupValidator.validate(artifact, home: root, keepWarm: [root.appendingPathComponent("project").path]))
    }
    func testReplacedTargetRejected() throws {
        let artifact = try makeDerived()
        try FileManager.default.moveItem(at: artifact.url, to: artifact.url.appendingPathExtension("old"))
        try FileManager.default.createDirectory(at: artifact.url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try CleanupValidator.validate(artifact, home: root))
    }
    func testSymlinkReplacementRejected() throws {
        let artifact = try makeDerived()
        let replacement = artifact.url.appendingPathExtension("old")
        try FileManager.default.moveItem(at: artifact.url, to: replacement)
        try FileManager.default.createSymbolicLink(at: artifact.url, withDestinationURL: replacement)
        XCTAssertThrowsError(try CleanupValidator.validate(artifact, home: root))
    }
    func testNestedWritesChangeFingerprint() throws {
        let artifact = try makeDerived()
        let before = try CleanupValidator.fingerprint(artifact.url)
        try Data("new build".utf8).write(to: artifact.url.appendingPathComponent("output"))
        XCTAssertNotEqual(before, try CleanupValidator.fingerprint(artifact.url))
    }
    func testFingerprintRejectsProtectedFiles() throws {
        let artifact = try makeDerived()
        try Data("secret".utf8).write(to: artifact.url.appendingPathComponent(".env"))
        XCTAssertThrowsError(try CleanupValidator.fingerprint(artifact.url))
    }
    func testSQLiteRoundTrip() async throws {
        let db = try SnapshotRepository(url: root.appendingPathComponent("history.sqlite"))
        var report = ScanReport(); report.directories = 42; report.issues = [.init("/denied", "권한 없음")]
        try await db.save(report, kind: "scan", id: report.id.uuidString)
        let loaded = try await db.load(ScanReport.self, kind: "scan")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].directories, 42)
        XCTAssertTrue(loaded[0].isPartial)
    }
    func testReportMasksAllUserHomes() throws {
        var report = ScanReport(); report.issues = [.init("/Users/alice/Library", "denied"), .init("/Users/bob/secret", "denied")]
        let text = String(decoding: try Diagnostics.maskedReport(report), as: UTF8.self)
        XCTAssertFalse(text.contains("alice")); XCTAssertFalse(text.contains("bob"))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(text.utf8)))
    }
    func testToolchainSkipsMetadataFiles() throws {
        try file("Library/Android/sdk/ndk/.DS_Store")
        try file("Library/Android/sdk/ndk/28.0/source.properties", "Pkg.Revision=28.0")
        let installations = ToolchainInspector.installations(home: root, environment: [:])
        XCTAssertEqual(installations.filter { $0.name == "Android ndk" }.map(\.version), ["28.0"])
    }
    func testBinaryUnits() {
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.bytes(1_073_741_824), "1.0 GiB")
        XCTAssertEqual(Format.bytes(-1024), "-1.0 KiB")
    }
    func testCancellationReturnsPartial() async {
        let options = ScanOptions(roots: [root], includeInventory: false)
        let task = Task { await Scanner.scan(options) }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.cancelled)
    }
}
