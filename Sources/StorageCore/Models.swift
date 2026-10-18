import Foundation

public enum Platform: String, Codable, CaseIterable, Sendable {
    case reactNative = "React Native", expo = "Expo", android = "Android", apple = "Apple", flutter = "Flutter", swift = "Swift", node = "Node.js"
}
public struct Project: Identifiable, Codable, Sendable {
    public var id: String { root.path }
    public var root: URL
    public var platforms: Set<Platform>
    public var evidence: [String]
    public var workspace: String?
    public var name: String { root.lastPathComponent }
}
public enum Risk: String, Codable, CaseIterable, Sendable {
    case safe = "정리 가능", review = "검토 필요", managed = "시스템 관리", protected = "사용자 데이터 보호"
}
public struct FileIdentity: Codable, Equatable, Sendable {
    public var device: UInt64
    public var inode: UInt64
    public var modifiedSeconds: Int64
    public var modifiedNanos: Int64
}
public struct Measurement: Codable, Sendable {
    public var logical: Int64 = 0
    public var allocated: Int64 = 0
    public var files: Int = 0
    public var issues: [CoverageIssue] = []
    public var complete: Bool { issues.isEmpty }
    public init() {}
}
public struct CoverageIssue: Codable, Identifiable, Sendable {
    public var id: String { path + reason }
    public var path: String
    public var reason: String
    public init(_ path: String, _ reason: String) { self.path = path; self.reason = reason }
}
public struct Artifact: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var owner: String
    public var projectID: String?
    public var risk: Risk
    public var policy: String
    public var reason: String
    public var measurement: Measurement
    public var identity: FileIdentity?
    public var scannedAt: Date = Date()
    public var canTrash: Bool { policy == "xcode-derived-child" && risk == .review && measurement.complete && identity != nil }
}
public struct Volume: Identifiable, Codable, Sendable {
    public var id: String
    public var url: URL
    public var name: String
    public var total: Int64
    public var available: Int64
    public var local: Bool
    public var removable: Bool
    public var used: Int64 { max(0, total - available) }
}
public struct ScanReport: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var startedAt = Date()
    public var finishedAt: Date?
    public var roots: [URL] = []
    public var projects: [Project] = []
    public var artifacts: [Artifact] = []
    public var issues: [CoverageIssue] = []
    public var directories = 0
    public var cancelled = false
    public var mode: String = "전체 분석"
    public var isPartial: Bool { cancelled || !issues.isEmpty || mode != "전체 분석" }
    public init() {}
}
public struct CleanupRecord: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var path: String
    public var status: String
    public var before: Int64
    public var after: Int64
    public var observedDelta: Int64 { after - before }
}
public enum Format {
    public static func bytes(_ value: Int64) -> String {
        let magnitude = abs(Double(value))
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        let index = magnitude > 0 ? min(4, max(0, Int(log(magnitude) / log(1024)))) : 0
        let scaled = Double(value) / pow(1024, Double(index))
        return index == 0 ? "\(value) B" : String(format: "%.1f %@", scaled, units[index])
    }
}
