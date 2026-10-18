import Foundation

public struct SDKPackage: Identifiable, Sendable, Equatable {
    public var id: String { root.path + "|" + packageID }
    public let root: URL
    public let manager: URL
    public let packageID: String
    public let version: String
    public let name: String
    public let location: URL
    public var bytes: Int64?
    public var removable: Bool {
        ["ndk", "platforms", "build-tools", "system-images", "cmake"].contains(packageID.components(separatedBy: ";").first ?? "")
    }
    public var restoreCommand: String { [manager.path, "--sdk_root=\(root.path)", packageID].map(ManagedCommand.displayArgument).joined(separator: " ") }
}
public struct SimulatorDevice: Identifiable, Sendable, Equatable {
    public var id: String { udid }
    public let udid: String
    public let name: String
    public let runtime: String
    public let state: String
    public let available: Bool
    public var bytes: Int64?
    public var canDelete: Bool { state == "Shutdown" && UUID(uuidString: udid) != nil }
}
public struct SimulatorRuntime: Identifiable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String
    public let available: Bool
    public var id: String { identifier }
}
public struct DeveloperInventory: Sendable {
    public var packages: [SDKPackage] = []
    public var devices: [SimulatorDevice] = []
    public var runtimes: [SimulatorRuntime] = []
    public var issues: [String] = []
    public init() {}
}
public struct ManagedRemovalPreview: Identifiable, Sendable {
    public let id = UUID()
    public let createdAt = Date()
    public let title: String
    public let impact: String
    public let command: String
    public let sdk: SDKPackage?
    public let device: SimulatorDevice?
    fileprivate let managerIdentity: FileIdentity?
}
public enum DeveloperManager {
    public static func parsePackages(_ output: String, root: URL, manager: URL) throws -> [SDKPackage] {
        guard output.contains("Installed packages:") else { throw CleanupError.blocked("SDK 목록 형식을 확인할 수 없습니다. Command-line Tools를 확인하세요.") }
        var result: [SDKPackage] = []
        for line in output.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 4, parts[0] != "Path", !parts[0].isEmpty else { continue }
            let idParts = parts[0].components(separatedBy: ";")
            guard idParts.allSatisfy({ !$0.isEmpty && $0.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil && $0 != "." && $0 != ".." }) else { continue }
            let relative = parts[3].replacingOccurrences(of: "\\", with: "/")
            guard !relative.hasPrefix("/"), !relative.isEmpty,
                  !relative.components(separatedBy: "/").contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { continue }
            let location = root.appendingPathComponent(relative)
            guard location.path.hasPrefix(root.path + "/") else { continue }
            result.append(SDKPackage(root: root, manager: manager, packageID: parts[0], version: parts[1], name: parts[2], location: location))
        }
        return result
    }
    public static func parseSimulators(_ data: Data) throws -> ([SimulatorDevice], [SimulatorRuntime]) {
        struct Device: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool? }
        struct Runtime: Decodable { let identifier: String; let name: String; let version: String; let isAvailable: Bool? }
        struct List: Decodable { let devices: [String: [Device]]; let runtimes: [Runtime] }
        let list = try JSONDecoder().decode(List.self, from: data)
        var devices: [SimulatorDevice] = []
        for (runtime, entries) in list.devices {
            for entry in entries where UUID(uuidString: entry.udid) != nil {
                devices.append(SimulatorDevice(udid: entry.udid, name: entry.name, runtime: runtime, state: entry.state, available: entry.isAvailable ?? false, bytes: nil))
            }
        }
        devices.sort { $0.name == $1.name ? $0.udid < $1.udid : $0.name < $1.name }
        return (devices, list.runtimes.map { SimulatorRuntime(identifier: $0.identifier, name: $0.name, version: $0.version, available: $0.isAvailable ?? false) })
    }
    static func installed(_ root: URL, manager: URL) throws -> [SDKPackage] {
        try parsePackages(ManagedCommand.checked(manager.path, ["--sdk_root=\(root.path)", "--list_installed"]), root: root, manager: manager)
    }
    static func simulators() throws -> ([SimulatorDevice], [SimulatorRuntime]) {
        let output = try ManagedCommand.checked("/usr/bin/xcrun", ["simctl", "list", "--json"])
        return try parseSimulators(Data(output.utf8))
    }
    public static func inventory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> DeveloperInventory {
        var result = DeveloperInventory()
        var roots = Set([home.appendingPathComponent("Library/Android/sdk").path])
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let path = ProcessInfo.processInfo.environment[key], path.hasPrefix("/") { roots.insert(path) }
        }
        for path in roots.sorted() {
            let root = URL(fileURLWithPath: FileSystem.canonicalPath(URL(fileURLWithPath: path)))
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let tools = root.appendingPathComponent("cmdline-tools")
            let versions = ((try? FileSystem.children(tools)) ?? []).sorted {
                if $0.lastPathComponent == "latest" { return $1.lastPathComponent != "latest" }
                if $1.lastPathComponent == "latest" { return false }
                return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
            }
            guard let manager = versions.map({ $0.appendingPathComponent("bin/sdkmanager") }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                result.issues.append("\(path): Android Studio의 SDK Tools에서 Command-line Tools를 설치하세요."); continue
            }
            do {
                for var package in try installed(root, manager: manager) {
                    if FileSystem.canonicalPath(package.location).hasPrefix(root.path + "/") {
                        let measurement = FileSystem.measure(package.location)
                        package.bytes = measurement.complete ? measurement.allocated : nil
                    }
                    if !result.packages.contains(where: { $0.id == package.id }) { result.packages.append(package) }
                }
            } catch { result.issues.append(error.localizedDescription) }
        }
        do {
            let (devices, runtimes) = try simulators()
            result.runtimes = runtimes
            result.devices = devices.map { device in
                var measured = device
                let path = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(device.udid)")
                let size = FileSystem.measure(path)
                measured.bytes = size.complete ? size.allocated : nil
                return measured
            }
        } catch { result.issues.append("Simulator: " + error.localizedDescription) }
        return result
    }
    public static func dependencyNotes(_ package: SDKPackage, projects: [Project], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        let components = package.packageID.components(separatedBy: ";")
        let needle = components.last ?? package.version
        var matches: [String] = []
        for project in projects where project.platforms.contains(.android) {
            let paths = ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts", "android/app/build.gradle", "android/app/build.gradle.kts", "gradle/libs.versions.toml"]
            if paths.contains(where: { FileSystem.readText(project.root.appendingPathComponent($0))?.contains(needle.replacingOccurrences(of: "android-", with: "")) == true }) {
                matches.append(project.name)
            }
        }
        if package.packageID.hasPrefix("system-images;") {
            let image = package.packageID.replacingOccurrences(of: ";", with: "/")
            for avd in (try? FileSystem.children(home.appendingPathComponent(".android/avd"))) ?? [] where avd.pathExtension == "avd" {
                if let config = FileSystem.readText(avd.appendingPathComponent("config.ini")), config.contains(image) {
                    matches.append("AVD " + avd.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return matches
    }
}

public actor DeveloperActions {
    private var issued: [UUID: Date] = [:]
    private var readPackages: @Sendable (URL, URL) throws -> [SDKPackage] = { try DeveloperManager.installed($0, manager: $1) }
    private var readDevices: @Sendable () throws -> [SimulatorDevice] = { try DeveloperManager.simulators().0 }
    private var command: @Sendable (String, [String]) throws -> String = { try ManagedCommand.checked($0, $1, timeout: 120) }
    private var idle: @Sendable ([String]) throws -> Void = { try ManagedCommand.requireIdle(owners: $0) }
    public init() {}
    init(readPackages: @escaping @Sendable (URL, URL) throws -> [SDKPackage], readDevices: @escaping @Sendable () throws -> [SimulatorDevice], command: @escaping @Sendable (String, [String]) throws -> String, idle: @escaping @Sendable ([String]) throws -> Void) {
        self.readPackages = readPackages; self.readDevices = readDevices; self.command = command; self.idle = idle
    }
    private func issue(_ preview: ManagedRemovalPreview) {
        issued = issued.filter { Date().timeIntervalSince($0.value) < 300 }
        issued[preview.id] = preview.createdAt
    }
    public func preview(sdk: SDKPackage, projects: [Project], keepWarm: Set<String>) throws -> ManagedRemovalPreview {
        guard sdk.removable else { throw CleanupError.blocked("도구 자체는 Android Studio에서 관리하세요.") }
        guard keepWarm.isEmpty else { throw CleanupError.blocked("공유 SDK를 보호하기 위해 Keep Warm이 설정된 동안 SDK 삭제를 차단합니다.") }
        let references = DeveloperManager.dependencyNotes(sdk, projects: projects)
        guard references.isEmpty else { throw CleanupError.blocked("이 SDK 버전을 참조할 수 있는 프로젝트: " + references.joined(separator: ", ")) }
        try validate(sdk)
        let preview = ManagedRemovalPreview(title: sdk.name + " · " + sdk.version,
            impact: "공유 SDK 패키지를 영구 제거합니다. 발견하지 못한 프로젝트·Gradle 간접 변수·AVD의 의존성은 확인되지 않았습니다. 사용 중인 프로젝트와 AVD를 직접 확인하세요. 복원은 동일 패키지를 재다운로드해야 하며 네트워크와 라이선스가 필요합니다.\n복원: " + sdk.restoreCommand,
            command: [sdk.manager.path, "--sdk_root=\(sdk.root.path)", "--uninstall", sdk.packageID].map(ManagedCommand.displayArgument).joined(separator: " "), sdk: sdk, device: nil,
            managerIdentity: try FileSystem.identity(sdk.manager))
        issue(preview); return preview
    }
    public func preview(device: SimulatorDevice) throws -> ManagedRemovalPreview {
        let current = try readDevices().first { $0.id == device.id }
        guard let current, current.canDelete, current.name == device.name, current.runtime == device.runtime else { throw CleanupError.blocked("기기가 변경되었거나 실행 중입니다. 종료 후 새로고침하세요.") }
        let preview = ManagedRemovalPreview(title: device.name, impact: "이 기기의 앱·사진·테스트 데이터가 영구 삭제됩니다. 런타임은 유지됩니다. 기기를 다시 만들어도 기존 데이터는 복원되지 않습니다.", command: "xcrun simctl delete \(device.udid)", sdk: nil, device: current, managerIdentity: nil)
        issue(preview); return preview
    }
    private func validate(_ sdk: SDKPackage) throws {
        guard sdk.removable, FileSystem.canonicalPath(sdk.root) == sdk.root.path,
              FileSystem.canonicalPath(sdk.manager).hasPrefix(sdk.root.path + "/cmdline-tools/"),
              FileSystem.canonicalPath(sdk.location) == sdk.location.path else { throw CleanupError.blocked("SDK 경로가 변경되었거나 허용 범위 밖입니다.") }
        guard let current = try readPackages(sdk.root, sdk.manager).first(where: { $0.packageID == sdk.packageID }),
              current.version == sdk.version, current.location == sdk.location else { throw CleanupError.blocked("SDK 상태가 변경되었습니다. 새로고침하세요.") }
    }
    public func execute(_ preview: ManagedRemovalPreview, keepWarm: Set<String>, projects: [Project]) throws -> CleanupRecord {
        guard issued.removeValue(forKey: preview.id) != nil, Date().timeIntervalSince(preview.createdAt) < 300 else { throw CleanupError.blocked("승인이 만료되었습니다. 다시 미리보기를 여세요.") }
        let before = try? VolumeInventory.read(VolumeInventory.dataRoot).available
        let path: String
        if let sdk = preview.sdk {
            guard keepWarm.isEmpty, DeveloperManager.dependencyNotes(sdk, projects: projects).isEmpty,
                  try FileSystem.identity(sdk.manager) == preview.managerIdentity else { throw CleanupError.blocked("SDK 보호 설정 또는 도구가 변경되었습니다.") }
            try idle(["gradle", "emulator", "qemu", "studio.app", "java", "flutter"])
            try validate(sdk)
            _ = try command(sdk.manager.path, ["--sdk_root=\(sdk.root.path)", "--uninstall", sdk.packageID])
            guard try !readPackages(sdk.root, sdk.manager).contains(where: { $0.packageID == sdk.packageID }) else { throw CleanupError.blocked("제거 완료를 확인하지 못했습니다. 새로고침하세요.") }
            path = sdk.location.path
        } else if let device = preview.device {
            guard let current = try readDevices().first(where: { $0.id == device.id }), current.canDelete,
                  current.name == device.name, current.runtime == device.runtime else { throw CleanupError.blocked("기기 상태가 변경되었습니다.") }
            _ = try command("/usr/bin/xcrun", ["simctl", "delete", device.udid])
            guard try !readDevices().contains(where: { $0.id == device.id }) else { throw CleanupError.blocked("기기 삭제 완료를 확인하지 못했습니다.") }
            path = device.udid
        } else { throw CleanupError.blocked("삭제 대상이 없습니다.") }
        let after = try? VolumeInventory.read(VolumeInventory.dataRoot).available
        return CleanupRecord(path: path, status: "공식 도구로 제거 완료 · " + preview.title, before: before, after: after, recoveryHint: preview.sdk?.restoreCommand ?? "기기를 다시 생성해도 삭제된 기기 데이터는 복구되지 않습니다.")
    }
}
