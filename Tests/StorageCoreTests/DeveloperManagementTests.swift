import XCTest
@testable import StorageCore

private final class FakeDeveloperTools: @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [SimulatorDevice] = []
    private var packages: [SDKPackage] = []
    private var calls: [[String]] = []
    func set(devices: [SimulatorDevice]) { lock.lock(); defer { lock.unlock() }; self.devices = devices }
    func set(packages: [SDKPackage]) { lock.lock(); defer { lock.unlock() }; self.packages = packages }
    func getDevices() -> [SimulatorDevice] { lock.lock(); defer { lock.unlock() }; return devices }
    func getPackages() -> [SDKPackage] { lock.lock(); defer { lock.unlock() }; return packages }
    func getCalls() -> [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
    func run(_ executable: String, _ arguments: [String]) -> String {
        lock.lock(); defer { lock.unlock() }
        calls.append([executable] + arguments)
        if arguments.contains("--uninstall") { packages = [] }
        if arguments.prefix(2) == ["simctl", "delete"] { devices.removeAll { $0.udid == arguments.last } }
        return ""
    }
    func engine() -> DeveloperActions {
        DeveloperActions(readPackages: { _, _ in self.getPackages() }, readDevices: { self.getDevices() }, command: { self.run($0, $1) }, idle: { _ in })
    }
}
final class DeveloperManagementTests: XCTestCase {
    func testSDKParserRejectsTraversalAndDistinguishesInfrastructure() throws {
        let text = """
        Installed packages:
        Path | Version | Description | Location
        ------- | ------- | ------- | -------
        ndk;26.1 | 26.1 | NDK | ndk/26.1
        platform-tools | 35.0 | Tools | platform-tools
        ndk;../bad | 1 | Bad | ../outside
        platforms;android-35 | 1 | Bad | /outside
        """
        let packages = try DeveloperManager.parsePackages(text, root: URL(fileURLWithPath: "/sdk"), manager: URL(fileURLWithPath: "/sdk/cmdline-tools/latest/bin/sdkmanager"))
        XCTAssertEqual(packages.count, 2)
        XCTAssertTrue(packages[0].removable); XCTAssertFalse(packages[1].removable)
        XCTAssertEqual(packages[0].location.path, "/sdk/ndk/26.1")
        XCTAssertThrowsError(try DeveloperManager.parsePackages("connection failed", root: URL(fileURLWithPath: "/sdk"), manager: URL(fileURLWithPath: "/tool")))
    }
    func testSimulatorParserKeepsUnavailableDevicesButRejectsInvalidIDs() throws {
        let text = #"{"devices":{"runtime":[{"udid":"00000000-0000-0000-0000-000000000001","name":"Old Phone","state":"Shutdown","isAvailable":false},{"udid":"all","name":"unsafe","state":"Shutdown"}]},"runtimes":[{"identifier":"runtime","name":"iOS","version":"18","isAvailable":false}]}"#
        let (devices, runtimes) = try DeveloperManager.parseSimulators(Data(text.utf8))
        XCTAssertEqual(devices.count, 1); XCTAssertTrue(devices[0].canDelete)
        XCTAssertFalse(devices[0].available); XCTAssertEqual(runtimes.count, 1)
        XCTAssertThrowsError(try DeveloperManager.parseSimulators(Data("{}".utf8)))
    }
    func testDeviceRemovalUsesSpecificUUIDAndApprovalOnlyOnce() async throws {
        let fake = FakeDeveloperTools(), engine = fake.engine()
        let device = SimulatorDevice(udid: "00000000-0000-0000-0000-000000000001", name: "Fixture", runtime: "runtime", state: "Shutdown", available: false)
        fake.set(devices: [device])
        let preview = try await engine.preview(device: device)
        let result = try await engine.execute(preview, keepWarm: [], projects: [])
        XCTAssertNil(result.failureReason)
        XCTAssertEqual(fake.getCalls(), [["/usr/bin/xcrun", "simctl", "delete", device.udid]])
        do { _ = try await engine.execute(preview, keepWarm: [], projects: []); XCTFail("Approval was reused") } catch {}
        XCTAssertEqual(fake.getCalls().count, 1)
    }
    func testDeviceBootedAfterPreviewCannotBeDeleted() async throws {
        let fake = FakeDeveloperTools(), engine = fake.engine()
        let device = SimulatorDevice(udid: "00000000-0000-0000-0000-000000000001", name: "Fixture", runtime: "runtime", state: "Shutdown", available: true)
        fake.set(devices: [device])
        let preview = try await engine.preview(device: device)
        fake.set(devices: [SimulatorDevice(udid: device.udid, name: device.name, runtime: device.runtime, state: "Booted", available: true)])
        do { _ = try await engine.execute(preview, keepWarm: [], projects: []); XCTFail("Booted device deleted") } catch {}
        XCTAssertTrue(fake.getCalls().isEmpty)
    }
    func testEraseKeepsDeviceAndUsesExactUUIDOnce() async throws {
        let fake = FakeDeveloperTools(), engine = fake.engine()
        let device = SimulatorDevice(udid: UUID().uuidString, name: "Fixture", runtime: "runtime", state: "Shutdown", available: true)
        fake.set(devices: [device])
        let preview = try await engine.preview(device: device, action: .erase)
        let record = try await engine.execute(preview, keepWarm: [], projects: [])
        XCTAssertTrue(record.status.contains("초기화"))
        XCTAssertEqual(fake.getDevices(), [device])
        XCTAssertEqual(fake.getCalls(), [["/usr/bin/xcrun", "simctl", "erase", device.udid]])
        do { _ = try await engine.execute(preview, keepWarm: [], projects: []); XCTFail("Reused") } catch {}
        XCTAssertEqual(fake.getCalls().count, 1)
    }
    func testBatchTargetsOnlySelectedDevicesAndBlocksChangedAvailability() async throws {
        let fake = FakeDeveloperTools(), engine = fake.engine()
        let selected = SimulatorDevice(udid: UUID().uuidString, name: "Old", runtime: "runtime", state: "Shutdown", available: false)
        let other = SimulatorDevice(udid: UUID().uuidString, name: "Keep", runtime: "runtime", state: "Shutdown", available: true)
        fake.set(devices: [selected, other])
        let batch = try await engine.preview(devices: [selected], action: .delete)
        XCTAssertEqual(batch.items.count, 1)
        _ = try await engine.execute(batch.items[0], keepWarm: [], projects: [])
        XCTAssertEqual(fake.getDevices(), [other])
        XCTAssertEqual(fake.getCalls().first?.last, selected.udid)
        fake.set(devices: [selected])
        let changed = try await engine.preview(device: selected)
        fake.set(devices: [SimulatorDevice(udid: selected.udid, name: selected.name, runtime: selected.runtime, state: "Shutdown", available: true)])
        do { _ = try await engine.execute(changed, keepWarm: [], projects: []); XCTFail("Changed availability") } catch {}
        XCTAssertEqual(fake.getCalls().count, 1)
    }
    func testCleanupRejectsEmptyDuplicateUnavailableEraseAndRunningDevices() async throws {
        let fake = FakeDeveloperTools(), engine = fake.engine()
        let unavailable = SimulatorDevice(udid: UUID().uuidString, name: "Old", runtime: "runtime", state: "Shutdown", available: false)
        let running = SimulatorDevice(udid: UUID().uuidString, name: "Running", runtime: "runtime", state: "Booted", available: true)
        fake.set(devices: [unavailable, running])
        do { _ = try await engine.preview(devices: [], action: .delete); XCTFail("Empty") } catch {}
        do { _ = try await engine.preview(devices: [unavailable, unavailable], action: .delete); XCTFail("Duplicate") } catch {}
        do { _ = try await engine.preview(device: unavailable, action: .erase); XCTFail("Unavailable erase") } catch {}
        do { _ = try await engine.preview(device: running, action: .erase); XCTFail("Running erase") } catch {}
        XCTAssertTrue(fake.getCalls().isEmpty)
    }
    func testEraseCommandFailureIsNotReportedAsSuccess() async throws {
        let device = SimulatorDevice(udid: UUID().uuidString, name: "Fixture", runtime: "runtime", state: "Shutdown", available: true)
        let engine = DeveloperActions(readPackages: { _, _ in [] }, readDevices: { [device] }, command: { _, _ in throw CleanupError.blocked("fixture failure") }, idle: { _ in })
        let preview = try await engine.preview(device: device, action: .erase)
        do { _ = try await engine.execute(preview, keepWarm: [], projects: []); XCTFail("Failure ignored") } catch {}
        do { _ = try await engine.execute(preview, keepWarm: [], projects: []); XCTFail("Failure approval reused") } catch {}
    }
    func testSDKRemovalPinsRootAndPackageAndRevalidatesKeepWarm() async throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: FileSystem.canonicalPath(raw))
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = root.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager")
        let location = root.appendingPathComponent("ndk/26.1")
        try FileManager.default.createDirectory(at: manager.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        try Data("fixture tool".utf8).write(to: manager)
        let sdk = SDKPackage(root: root, manager: manager, packageID: "ndk;26.1", version: "26.1", name: "NDK", location: location)
        let fake = FakeDeveloperTools(), engine = fake.engine(); fake.set(packages: [sdk])
        let blocked = try await engine.preview(sdk: sdk, projects: [], keepWarm: [])
        do { _ = try await engine.execute(blocked, keepWarm: ["/project"], projects: []); XCTFail("Keep Warm ignored") } catch {}
        XCTAssertTrue(fake.getCalls().isEmpty)
        let approved = try await engine.preview(sdk: sdk, projects: [], keepWarm: [])
        _ = try await engine.execute(approved, keepWarm: [], projects: [])
        XCTAssertEqual(fake.getCalls(), [[manager.path, "--sdk_root=\(root.path)", "--uninstall", "ndk;26.1"]])
    }
    func testKnownAVDReferenceBlocksSystemImageCandidate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let avd = root.appendingPathComponent(".android/avd/Fixture.avd")
        try FileManager.default.createDirectory(at: avd, withIntermediateDirectories: true)
        try Data("image.sysdir.1=system-images/android-35/google_apis/arm64-v8a/".utf8).write(to: avd.appendingPathComponent("config.ini"))
        let sdk = SDKPackage(root: root, manager: root.appendingPathComponent("tool"), packageID: "system-images;android-35;google_apis;arm64-v8a", version: "1", name: "Image", location: root.appendingPathComponent("image"))
        XCTAssertEqual(DeveloperManager.dependencyNotes(sdk, projects: [], home: root), ["AVD Fixture"])
    }
    func testCommandRunnerCapturesStatusAndEnforcesTimeout() throws {
        let output = try ManagedCommand.run("/usr/bin/printf", ["hello %s", "fixture"])
        XCTAssertEqual(output.status, 0); XCTAssertEqual(output.output, "hello fixture")
        XCTAssertThrowsError(try ManagedCommand.checked("/usr/bin/false", []))
        XCTAssertThrowsError(try ManagedCommand.run("/bin/sleep", ["2"], timeout: 0.05))
        XCTAssertThrowsError(try ManagedCommand.run("relative", []))
        XCTAssertEqual(ManagedCommand.displayArgument("/sdk/$(unsafe)"), "'/sdk/$(unsafe)'")
        XCTAssertEqual(ManagedCommand.displayArgument("a'b"), "'a'\\''b'")
    }
}
