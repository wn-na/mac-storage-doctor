import Foundation

public enum ArtifactKind: String, CaseIterable, Sendable {
    case build = "빌드 생성물", dependencies = "설치 의존성", cache = "공유 캐시", sdk = "SDK · 시뮬레이터", user = "사용자 데이터", system = "시스템 관리"
}
public extension Artifact {
    var kind: ArtifactKind {
        if policy == "xcode-derived-child" { return .build }
        if projectID != nil { return ["node_modules", "Pods"].contains(url.lastPathComponent) ? .dependencies : .build }
        if risk == .protected { return .user }
        if ["Simulator", "Android SDK", "Android AVD", "Xcode DeviceSupport"].contains(owner) { return .sdk }
        return risk == .managed ? .system : .cache
    }
    var cleanupMethod: String {
        if canTrash { return "선택 정리 → 휴지통 이동" }
        if kind == .sdk { return "SDK · 시뮬레이터에서 개별 관리" }
        if risk == .protected { return "보호됨 · 앱에서 직접 관리" }
        return "공식 도구에서 관리 · 직접 정리 제외"
    }
    var quickEligible: Bool { canTrash && (policy == "xcode-derived-child" || (policy == "project-generated" && kind == .build)) }
}
public enum CleanupCatalog {
    public static func upgrade(_ report: ScanReport) -> ScanReport {
        var updated = report
        updated.artifacts = report.artifacts.map { original in
            var item = original
            if item.policy == "project-diagnosis", let project = report.projects.first(where: { $0.id == item.projectID }),
               allowedPaths(project).contains(where: { project.root.appendingPathComponent($0) == item.url }) {
                item.policy = "project-generated"
                item.reason = "재빌드·의존성 재설치가 필요합니다. 로컬 수정은 휴지통에서 복원하세요. 실행 전 프로젝트와 경로를 재검증합니다."
            }
            return item
        }
        return updated
    }

    public static func allowedPaths(_ project: Project) -> Set<String> {
        var paths = Set<String>()
        if !project.platforms.isDisjoint(with: [.node, .reactNative, .expo]) { paths.insert("node_modules") }
        if project.platforms.contains(.flutter) { paths.formUnion(["build", ".dart_tool"]) }
        if project.platforms.contains(.android) { paths.formUnion([".gradle", ".cxx", "app/build", "android/.gradle", "android/app/build"]) }
        if project.platforms.contains(.swift) { paths.insert(".build") }
        // Pods may contain manually maintained local pod source, so remain diagnostic only.
        return paths
    }
    public static func top(_ artifacts: [Artifact], limit: Int = 10) -> [Artifact] {
        artifacts.sorted { $0.measurement.allocated == $1.measurement.allocated ? $0.id < $1.id : $0.measurement.allocated > $1.measurement.allocated }.prefix(max(0, limit)).map { $0 }
    }
}

public enum AnalysisSchedule {
    public static func due(last: Date, now: Date = Date(), intervalHours: Int) -> Bool {
        now.timeIntervalSince(last) >= Double(max(1, intervalHours)) * 3600
    }
    public static func delay(lastIncremental: Date, now: Date = Date(), minutes: Int) -> TimeInterval {
        max(30, Double(max(5, minutes)) * 60 - now.timeIntervalSince(lastIncremental))
    }
}
