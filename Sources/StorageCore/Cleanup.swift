import Foundation
import Darwin

public enum CleanupError: LocalizedError {
    case blocked(String)
    public var errorDescription: String? { if case .blocked(let reason) = self { return reason }; return nil }
}
public struct CleanupPreview: Sendable, Identifiable {
    public let id: UUID
    public let artifact: Artifact
    public let createdAt: Date
    public let fingerprint: UInt64
    fileprivate init(artifact: Artifact, fingerprint: UInt64) { id = UUID(); self.artifact = artifact; createdAt = Date(); self.fingerprint = fingerprint }
}
public enum CleanupValidator {
    public static func validate(_ artifact: Artifact, home: URL = FileManager.default.homeDirectoryForCurrentUser, keepWarm: Set<String> = []) throws {
        guard artifact.canTrash else { throw CleanupError.blocked("등록된 실행 정책이 없는 항목입니다.") }
        let url = artifact.url
        let allowed = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard url.deletingLastPathComponent() == allowed, url != allowed,
              FileSystem.canonicalPath(url) == url.path else { throw CleanupError.blocked("허용 경로 밖이거나 심볼릭 링크입니다.") }
        var ancestor = url
        while ancestor.path != "/" {
            guard !FileSystem.isLink(try FileSystem.metadata(ancestor)) else { throw CleanupError.blocked("상위 경로가 심볼릭 링크입니다: \(ancestor.path)") }
            ancestor.deleteLastPathComponent()
        }
        guard try FileSystem.identity(url) == artifact.identity else { throw CleanupError.blocked("분석 후 대상이 변경되었습니다. 다시 검사하세요.") }
        guard FileSystem.isDirectory(try FileSystem.metadata(url)) else { throw CleanupError.blocked("디렉터리가 아닙니다.") }
        let data = try Data(contentsOf: url.appendingPathComponent("info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let workspace = info["WorkspacePath"] as? String, workspace.hasPrefix("/") else { throw CleanupError.blocked("Xcode 소유 정보를 확인할 수 없습니다.") }
        guard !keepWarm.contains(where: { workspace == $0 || workspace.hasPrefix($0 + "/") }) else { throw CleanupError.blocked("Keep Warm 프로젝트의 빌드 캐시입니다.") }
    }
    // A complete metadata pass detects writes under the target, not only a changed root inode.
    public static func fingerprint(_ root: URL) throws -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        var queue = [root]
        let initial = try FileSystem.metadata(root)
        while let url = queue.popLast() {
            try Task.checkCancellation()
            let s = try FileSystem.metadata(url)
            guard s.st_dev == initial.st_dev, !FileSystem.isLink(s) else { throw CleanupError.blocked("링크 또는 마운트 경계가 포함되어 있습니다.") }
            guard ![".git", ".env", ".ssh"].contains(url.lastPathComponent), !["keystore", "p12", "mobileprovision"].contains(url.pathExtension) else { throw CleanupError.blocked("보호 파일이 포함되어 있습니다.") }
            let value = "\(url.path)|\(s.st_dev)|\(s.st_ino)|\(s.st_size)|\(s.st_mtimespec.tv_sec)|\(s.st_mtimespec.tv_nsec)|\(s.st_ctimespec.tv_sec)|\(s.st_ctimespec.tv_nsec)"
            for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            if FileSystem.isDirectory(s) { queue += try FileSystem.children(url).sorted { $0.path < $1.path } }
        }
        return hash
    }
}
public actor CleanupEngine {
    private var issued = Set<UUID>()
    public init() {}
    private func checkProcesses() throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-axo", "comm="]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CleanupError.blocked("실행 중인 작업을 확인할 수 없습니다.") }
        let commands = String(decoding: data, as: UTF8.self).lowercased()
        for owner in ["xcode.app/", "xcodebuild", "swift-frontend", "swift-build", "clang", "ibtoold", "xcbuild", "sourcekit", "flutter", "gradle"] where commands.contains(owner) {
            throw CleanupError.blocked("개발 작업 실행 중: \(owner). 작업과 IDE를 종료한 뒤 다시 시도하세요.")
        }
    }
    public func preview(_ artifact: Artifact, keepWarm: Set<String>) throws -> CleanupPreview {
        try CleanupValidator.validate(artifact, keepWarm: keepWarm)
        try checkProcesses()
        let preview = CleanupPreview(artifact: artifact, fingerprint: try CleanupValidator.fingerprint(artifact.url))
        issued.insert(preview.id)
        return preview
    }
    public func execute(_ preview: CleanupPreview, keepWarm: Set<String>) throws -> CleanupRecord {
        guard issued.remove(preview.id) != nil, Date().timeIntervalSince(preview.createdAt) < 300 else { throw CleanupError.blocked("만료되었거나 이미 실행한 승인입니다. 미리보기를 다시 여세요.") }
        try CleanupValidator.validate(preview.artifact, keepWarm: keepWarm)
        try checkProcesses()
        guard try CleanupValidator.fingerprint(preview.artifact.url) == preview.fingerprint else { throw CleanupError.blocked("미리보기 이후 내용이 바뀌었습니다.") }
        let before = try VolumeInventory.read(preview.artifact.url).available
        try CleanupValidator.validate(preview.artifact, keepWarm: keepWarm)
        var trashURL: NSURL?
        try FileManager.default.trashItem(at: preview.artifact.url, resultingItemURL: &trashURL)
        let after = (try? VolumeInventory.read(preview.artifact.url.deletingLastPathComponent()).available) ?? before
        return CleanupRecord(path: preview.artifact.url.path, status: "휴지통 이동 완료 · 비우기 전 미회수", before: before, after: after)
    }
}
