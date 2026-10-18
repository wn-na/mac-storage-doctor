import Foundation

public enum Inventory {
    public static func candidates(projects: [Project], includeShared: Bool = true, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Artifact] {
        var items: [Artifact] = []
        func add(_ url: URL, _ owner: String, _ risk: Risk, _ policy: String, _ reason: String, project: String? = nil) {
            guard let s = try? FileSystem.metadata(url), !FileSystem.isLink(s) else { return }
            items.append(Artifact(url: url, owner: owner, projectID: project, risk: risk, policy: policy, reason: reason, measurement: Measurement(), identity: try? FileSystem.identity(url)))
        }
        for p in projects {
            var paths: [String] = []
            if !p.platforms.isDisjoint(with: [.node, .reactNative, .expo]) { paths += ["node_modules", ".expo"] }
            if p.platforms.contains(.flutter) { paths += ["build", ".dart_tool"] }
            if p.platforms.contains(.android) { paths += [".gradle", ".cxx", "app/build", "android/.gradle", "android/app/build"] }
            if p.platforms.contains(.apple) { paths += ["Pods", "ios/Pods"] }
            if p.platforms.contains(.swift) { paths += [".build"] }
            for path in Set(paths) {
                add(p.root.appendingPathComponent(path), p.name, .review, "project-diagnosis", "재빌드·의존성 재설치 필요. 프로젝트의 공식 도구에서 정리하세요.", project: p.id)
            }
        }
        guard includeShared else { return items }
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        for child in (try? FileSystem.children(derived)) ?? [] {
            // Only Xcode entries with a workspace association are eligible for a preview.
            let plist = child.appendingPathComponent("info.plist")
            let data = try? Data(contentsOf: plist)
            let info = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            let workspace = info?["WorkspacePath"] as? String
            add(child, "Xcode DerivedData", .review, workspace == nil ? "diagnosis" : "xcode-derived-child", "Xcode 빌드 캐시. Xcode·빌드 작업 종료 필요. 휴지통 이동 후 다시 빌드해야 합니다.")
        }
        let entries: [(String, String, Risk, String)] = [
            (".npm", "npm", .review, "npm cache clean 등 공식 명령 사용"),
            (".gradle/caches", "Gradle", .review, "공유 의존성 캐시: 모든 빌드의 재다운로드에 영향"),
            (".pub-cache", "Dart / Flutter Pub", .review, "공유 Pub 캐시: 공식 도구에서 관리"),
            ("Library/Caches/CocoaPods", "CocoaPods", .review, "pod cache clean 등 공식 명령 사용"),
            ("Library/Caches/pip", "pip", .review, "pip cache purge 등 공식 명령 사용"),
            ("Library/Caches/Homebrew", "Homebrew", .review, "brew cleanup --dry-run으로 영향 확인"),
            ("Library/Developer/Xcode/Archives", "Xcode Archives", .protected, "배포 아카이브와 디버깅 심볼 보존"),
            ("Library/Developer/Xcode/iOS DeviceSupport", "Xcode DeviceSupport", .managed, "Xcode에서 버전별 관리"),
            ("Library/Developer/CoreSimulator", "Simulator", .managed, "Xcode의 Platforms / Devices에서 관리"),
            ("Library/Android/sdk", "Android SDK", .managed, "Android Studio SDK Manager에서 관리"),
            (".android/avd", "Android AVD", .managed, "Android Studio Device Manager에서 관리"),
            (".vscode/extensions", "VS Code Extensions", .managed, "VS Code 확장 관리에서 활성 버전 확인"),
            (".cursor/extensions", "Cursor Extensions", .managed, "Cursor 확장 관리에서 활성 버전 확인"),
            ("Library/Application Support", "앱 데이터", .protected, "DB·대화·모델·오프라인 데이터 포함. 일괄 삭제 금지"),
            ("Library/Containers", "앱 컨테이너", .protected, "앱별 사용자 데이터 보존"),
            ("Library/Logs", "앱 로그", .protected, "소유자와 사용 상태를 확정하지 않은 로그 보존")
        ]
        for (path, owner, risk, reason) in entries { add(home.appendingPathComponent(path), owner, risk, "diagnosis", reason) }
        for (path, owner) in [("/System/Library/AssetsV2", "Apple MobileAsset"), ("/private/var/vm", "VM / Swap"), ("/private/var/folders", "시스템 임시 데이터"), ("/Library/Caches", "시스템 캐시")] {
            add(URL(fileURLWithPath: path), owner, .managed, "diagnosis", "macOS 관리 데이터. 직접 삭제하지 않습니다.")
        }
        for path in ["ANDROID_HOME", "ANDROID_SDK_ROOT", "FLUTTER_ROOT", "PUB_CACHE", "GRADLE_USER_HOME"] {
            if let value = ProcessInfo.processInfo.environment[path], value.hasPrefix("/") { add(URL(fileURLWithPath: value), path, .managed, "diagnosis", "환경변수로 발견. 환경 설정은 변경하지 않습니다.") }
        }
        // Avoid nested inventories contributing twice. Project-owned artifacts take priority.
        return items.filter { candidate in
            !items.contains { other in other.id != candidate.id && candidate.url.path.hasPrefix(other.url.path + "/") }
        }.reduce(into: []) { result, item in if !result.contains(where: { $0.id == item.id }) { result.append(item) } }
    }
}
