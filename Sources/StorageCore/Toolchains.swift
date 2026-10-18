import Foundation

public struct ToolInstallation: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public var name: String
    public var version: String
    public var url: URL
    public var identity: String
}
public enum ToolchainInspector {
    public static func installations(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) -> [ToolInstallation] {
        var result: [ToolInstallation] = []
        for root in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            for url in (try? FileSystem.children(root)) ?? [] where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                let owners: [String: String] = ["com.apple.dt.Xcode": "Xcode", "com.google.android.studio": "Android Studio", "com.microsoft.VSCode": "Visual Studio Code", "com.todesktop.230313mzl4w4u92": "Cursor", "com.unity3d.unityhub": "Unity Hub", "com.docker.docker": "Docker"]
                guard let name = owners[id] else { continue }
                result.append(.init(name: name, version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown", url: url, identity: id))
            }
        }
        var sdkRoots = [home.appendingPathComponent("Library/Android/sdk")]
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let value = environment[key], value.hasPrefix("/") { sdkRoots.append(URL(fileURLWithPath: value)) }
        }
        for root in sdkRoots {
            for group in ["ndk", "build-tools", "platforms", "system-images"] {
                for version in (try? FileSystem.children(root.appendingPathComponent(group))) ?? [] {
                    guard let metadata = try? FileSystem.metadata(version), FileSystem.isDirectory(metadata), !version.lastPathComponent.hasPrefix(".") else { continue }
                    result.append(.init(name: "Android \(group)", version: version.lastPathComponent, url: version, identity: "SDK: \(root.path)"))
                }
            }
        }
        for key in ["FLUTTER_ROOT", "PUB_CACHE", "GRADLE_USER_HOME"] {
            if let value = environment[key], value.hasPrefix("/"), FileManager.default.fileExists(atPath: value) {
                result.append(.init(name: key, version: "Unknown", url: URL(fileURLWithPath: value), identity: "환경변수 · 읽기 전용"))
            }
        }
        let versionRoots = [("Flutter FVM", home.appendingPathComponent("fvm/versions")), ("Flutter FVM", home.appendingPathComponent(".fvm/versions")), ("Flutter Puro", home.appendingPathComponent(".puro/envs")), ("Unity Editor", URL(fileURLWithPath: "/Applications/Unity/Hub/Editor"))]
        for (name, root) in versionRoots {
            for child in (try? FileSystem.children(root)) ?? [] where !child.lastPathComponent.hasPrefix(".") { guard let metadata = try? FileSystem.metadata(child), FileSystem.isDirectory(metadata) else { continue }; result.append(.init(name: name, version: child.lastPathComponent, url: child, identity: "버전 관리자 설치 경로")) }
        }
        return result.reduce(into: []) { entries, next in if !entries.contains(where: { $0.id == next.id }) { entries.append(next) } }
    }
    public static func ndkRequirements(projects: [Project], installations: [ToolInstallation]) -> String {
        var result: [String] = []
        let installed = Set(installations.filter { $0.name == "Android ndk" }.map(\.version))
        let expression = try? NSRegularExpression(pattern: #"ndkVersion\s*(?:=\s*)?["']([^"']+)["']"#)
        for project in projects where project.platforms.contains(.android) {
            var versions = Set<String>()
            for relative in ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts", "android/build.gradle", "android/build.gradle.kts", "android/app/build.gradle", "android/app/build.gradle.kts"] {
                guard let text = FileSystem.readText(project.root.appendingPathComponent(relative)) else { continue }
                for match in expression?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
                    if let range = Range(match.range(at: 1), in: text) { versions.insert(String(text[range])) }
                }
            }
            if versions.isEmpty { result.append("\(project.name): Unknown — 간접 변수·버전 카탈로그는 확인되지 않음") }
            else { for version in versions.sorted() { result.append("\(project.name): NDK \(version) · \(installed.contains(version) ? "설치 발견 (SDK 루트 호환성 별도 확인)" : "미설치 또는 다른 SDK 경로 — SDK Manager에서 설치 필요")") } }
        }
        return result.isEmpty ? "Android 프로젝트를 전체 분석한 뒤 요구 버전을 확인할 수 있습니다." : result.joined(separator: "\n")
    }
}
public struct MobileAsset: Identifiable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var version: String
    public var build: String
    public var measurement: Measurement
}
public enum MobileAssetInspector {
    public static func scan(root: URL = URL(fileURLWithPath: "/System/Library/AssetsV2")) -> [MobileAsset] {
        var result: [MobileAsset] = []
        for category in (try? FileSystem.children(root)) ?? [] where category.lastPathComponent.localizedCaseInsensitiveContains("SimulatorRuntime") {
            for asset in (try? FileSystem.children(category)) ?? [] where asset.pathExtension == "asset" {
                if Task.isCancelled { return result }
                let info = asset.appendingPathComponent("Info.plist")
                guard let data = try? Data(contentsOf: info), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let properties = plist["MobileAssetProperties"] as? [String: Any] ?? plist
                result.append(.init(url: asset, version: properties["OSVersion"] as? String ?? "Unknown", build: properties["Build"] as? String ?? "Unknown", measurement: FileSystem.measure(asset)))
            }
        }
        return result
    }
}
