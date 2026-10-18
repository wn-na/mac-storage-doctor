import Foundation

public enum ProjectClassifier {
    public static func detect(_ root: URL) -> Project? {
        guard let children = try? FileSystem.children(root) else { return nil }
        let names = Set(children.map(\.lastPathComponent))
        var platforms = Set<Platform>(), evidence: [String] = []
        if let text = FileSystem.readText(root.appendingPathComponent("package.json")),
           let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let dependencies = (json["dependencies"] as? [String: Any] ?? [:]).merging(json["devDependencies"] as? [String: Any] ?? [:]) { a, _ in a }
            if dependencies["react-native"] != nil { platforms.insert(.reactNative); evidence.append("package.json: react-native") }
            if dependencies["expo"] != nil { platforms.insert(.expo); evidence.append("package.json: expo") }
            if platforms.isEmpty { platforms.insert(.node); evidence.append("package.json") }
        }
        if let yaml = FileSystem.readText(root.appendingPathComponent("pubspec.yaml")),
           yaml.range(of: #"(?m)^\s+flutter:\s*\n\s+sdk:\s*flutter\s*(?:#.*)?$"#, options: .regularExpression) != nil {
            platforms.insert(.flutter); evidence.append("pubspec.yaml: Flutter SDK dependency")
        }
        if names.contains("settings.gradle") || names.contains("settings.gradle.kts") {
            let settings = FileSystem.readText(root.appendingPathComponent("settings.gradle.kts")) ?? FileSystem.readText(root.appendingPathComponent("settings.gradle")) ?? ""
            let build = FileSystem.readText(root.appendingPathComponent("build.gradle.kts")) ?? FileSystem.readText(root.appendingPathComponent("build.gradle")) ?? ""
            let appBuild = FileSystem.readText(root.appendingPathComponent("app/build.gradle.kts")) ?? FileSystem.readText(root.appendingPathComponent("app/build.gradle")) ?? ""
            if (settings + build + appBuild).contains("com.android.") || names.contains("gradlew") {
                platforms.insert(.android); evidence.append("Gradle settings / wrapper / Android plugin")
            }
        }
        if children.contains(where: { $0.pathExtension == "xcodeproj" && FileManager.default.fileExists(atPath: $0.appendingPathComponent("project.pbxproj").path) }) {
            platforms.insert(.apple); evidence.append("Xcode project.pbxproj")
        }
        if let swift = FileSystem.readText(root.appendingPathComponent("Package.swift")), swift.contains("Package(") {
            platforms.insert(.swift); evidence.append("Swift package manifest")
            if swift.contains(".iOS(") || swift.contains(".macOS(") { platforms.insert(.apple) }
        }
        if !platforms.isDisjoint(with: [.flutter, .reactNative, .expo]) {
            if names.contains("android") { platforms.insert(.android) }
            if names.contains("ios") || names.contains("macos") { platforms.insert(.apple) }
        }
        guard !platforms.isEmpty else { return nil }
        return Project(root: root, platforms: platforms, evidence: evidence)
    }
    public static func group(_ input: [Project]) -> [Project] {
        let sorted = input.sorted { $0.root.path.count < $1.root.path.count }
        var results: [Project] = []
        for var project in sorted {
            project.workspace = nil
            let parent = results.last { project.root.path.hasPrefix($0.root.path + "/") }
            if let parent {
                let relative = String(project.root.path.dropFirst(parent.root.path.count + 1))
                if !parent.platforms.isDisjoint(with: [.flutter, .reactNative, .expo]), ["android", "ios", "macos", ".android", ".ios"].contains(relative) { continue }
                project.workspace = parent.id
            }
            results.append(project)
        }
        return results
    }
}

public final class ScanControl: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false
    public init() {}
    public func setPaused(_ value: Bool) { lock.lock(); paused = value; lock.unlock() }
    private func isPaused() -> Bool { lock.lock(); defer { lock.unlock() }; return paused }
    public func checkpoint() async throws {
        try Task.checkCancellation()
        while isPaused() { try await Task.sleep(for: .milliseconds(150)); try Task.checkCancellation() }
    }
}
public struct ScanOptions: Sendable {
    public var roots: [URL]
    public var exclusions: [String]
    public var quick: Bool
    public var includeInventory: Bool
    public init(roots: [URL] = [VolumeInventory.dataRoot], exclusions: [String] = [], quick: Bool = false, includeInventory: Bool = true) {
        self.roots = roots; self.exclusions = exclusions; self.quick = quick; self.includeInventory = includeInventory
    }
}
public enum Scanner {
    private static let pruned: Set<String> = ["node_modules", ".git", ".gradle", ".build", ".dart_tool", "Pods", "DerivedData", ".Trash"]
    public static func scan(_ options: ScanOptions, control: ScanControl = ScanControl(), progress: @escaping @Sendable (Int, String) async -> Void = { _, _ in }) async -> ScanReport {
        var report = ScanReport(); report.roots = options.roots; report.mode = options.quick ? "빠른 분석" : "전체 분석"
        let defaultCloudExclusions = ["Library/Mobile Documents", "Library/CloudStorage"].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0).path }
        let exclusions = (options.exclusions + defaultCloudExclusions).map { FileSystem.canonicalPath(URL(fileURLWithPath: $0)) }
        var seen = Set<String>()
        for root in options.roots {
            guard let first = try? FileSystem.metadata(root) else { report.issues.append(.init(root.path, "루트 접근 불가 또는 연결 해제")); continue }
            var queue = [root]
            while let directory = queue.popLast() {
                do { try await control.checkpoint() } catch { report.cancelled = true; break }
                if exclusions.contains(where: { FileSystem.canonicalPath(directory) == $0 || FileSystem.canonicalPath(directory).hasPrefix($0 + "/") }) {
                    report.issues.append(.init(directory.path, "사용자 제외")); continue
                }
                do {
                    let s = try FileSystem.metadata(directory)
                    guard !FileSystem.isLink(s), FileSystem.isDirectory(s) else { continue }
                    guard s.st_dev == first.st_dev else { report.issues.append(.init(directory.path, "볼륨 경계: 별도 선택 필요")); continue }
                    guard seen.insert("\(s.st_dev):\(s.st_ino)").inserted else { continue }
                    report.directories += 1
                    if report.directories % 100 == 0 { await progress(report.directories, directory.path) }
                    if let project = ProjectClassifier.detect(directory) { report.projects.append(project) }
                    for child in try FileSystem.children(directory) {
                        if pruned.contains(child.lastPathComponent) || child.pathExtension == "app" || child.pathExtension == "xcodeproj" {
                            report.issues.append(.init(child.path, "생성물·저장소 메타데이터·앱 번들: 프로젝트 내부 탐색 생략")); continue
                        }
                        if let m = try? FileSystem.metadata(child), FileSystem.isDirectory(m) { queue.append(FileSystem.visibleURL(child)) }
                    }
                } catch { report.issues.append(.init(directory.path, error.localizedDescription)) }
            }
            if report.cancelled { break }
        }
        report.projects = ProjectClassifier.group(report.projects)
        if !Task.isCancelled {
            let candidates = Inventory.candidates(projects: report.projects, includeShared: options.includeInventory)
            var measured = Set<String>()
            for var artifact in candidates {
                if exclusions.contains(where: { artifact.url.path == $0 || artifact.url.path.hasPrefix($0 + "/") || $0.hasPrefix(artifact.url.path + "/") }) {
                    report.issues.append(.init(artifact.url.path, "제외 경로를 포함하는 측정 대상 생략")); continue
                }
                do { try await control.checkpoint() } catch { report.cancelled = true; break }
                if Task.isCancelled { report.cancelled = true; break }
                await progress(report.directories, "측정: " + artifact.url.path)
                guard let identity = try? FileSystem.identity(artifact.url), measured.insert("\(identity.device):\(identity.inode)").inserted else { continue }
                artifact.measurement = FileSystem.measure(artifact.url)
                artifact.identity = identity
                report.artifacts.append(artifact)
                report.issues += artifact.measurement.issues
            }
        } else { report.cancelled = true }
        report.finishedAt = Date()
        return report
    }
}
