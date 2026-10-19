import Foundation
import Darwin

struct InodeKey: Hashable {
    let device: dev_t
    let inode: ino_t
}

public enum FileSystem {
    public static func canonicalPath(_ url: URL) -> String {
        guard let pointer = realpath(url.path, nil) else { return url.path }
        defer { free(pointer) }
        return String(cString: pointer)
    }
    /// Preserve the user-facing firmlink path only after verifying filesystem identity.
    public static func visibleURL(_ url: URL) -> URL {
        let prefix = "/System/Volumes/Data/"
        guard url.path.hasPrefix(prefix) else { return url }
        let visible = URL(fileURLWithPath: "/" + url.path.dropFirst(prefix.count))
        guard let original = try? metadata(url), let alias = try? metadata(visible),
              original.st_dev == alias.st_dev, original.st_ino == alias.st_ino else { return url }
        return visible
    }
    public static func metadata(_ url: URL) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return value
    }
    public static func identity(_ url: URL) throws -> FileIdentity {
        let s = try metadata(url)
        return FileIdentity(device: UInt64(s.st_dev), inode: UInt64(s.st_ino), modifiedSeconds: Int64(s.st_mtimespec.tv_sec), modifiedNanos: Int64(s.st_mtimespec.tv_nsec))
    }
    public static func isDirectory(_ s: stat) -> Bool { (s.st_mode & S_IFMT) == S_IFDIR }
    public static func isLink(_ s: stat) -> Bool { (s.st_mode & S_IFMT) == S_IFLNK }
    public static func children(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
    public static func readText(_ url: URL, limit: Int = 1_048_576) -> String? {
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return nil }
        guard let s = try? metadata(url), !isLink(s), s.st_size <= limit,
              (s.st_mode & S_IFMT) == S_IFREG else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    public static func measure(_ root: URL) -> Measurement {
        var result = Measurement()
        guard let initial = try? metadata(root) else {
            result.issues.append(.init(root.path, "읽을 수 없음")); return result
        }
        var queue = [root], seen = Set<InodeKey>()
        while let url = queue.popLast() {
            if Task.isCancelled { result.issues.append(.init(root.path, "측정 취소")); break }
            do {
                let s = try metadata(url)
                guard s.st_dev == initial.st_dev else { result.issues.append(.init(url.path, "다른 파일시스템: 중복 집계 제외")); continue }
                if isLink(s) { continue }
                // Single-link files cannot occur twice in this non-symlink traversal.
                // Retain identities only for directories and multiply-linked files.
                if isDirectory(s) || s.st_nlink > 1 {
                    let key = InodeKey(device: s.st_dev, inode: s.st_ino)
                    guard seen.insert(key).inserted else { continue }
                }
                result.allocated += Int64(s.st_blocks) * 512
                if isDirectory(s) { queue += try children(url) }
                else { result.logical += Int64(s.st_size); result.files += 1 }
            } catch { result.issues.append(.init(url.path, error.localizedDescription)) }
        }
        return result
    }
}
public enum VolumeInventory {
    public static func read(_ url: URL) throws -> Volume {
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsLocalKey, .volumeIsRemovableKey]
        let v = try url.resourceValues(forKeys: keys)
        guard let total = v.volumeTotalCapacity, let available = v.volumeAvailableCapacity else { throw CocoaError(.fileReadUnknown) }
        return Volume(id: v.volumeUUIDString ?? url.path, url: url, name: v.volumeName ?? url.lastPathComponent, total: Int64(total), available: Int64(available), local: v.volumeIsLocal ?? false, removable: v.volumeIsRemovable ?? false)
    }
    public static func mounted() -> [Volume] {
        (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsLocalKey], options: []) ?? []).compactMap { try? read($0) }
    }
    public static var dataRoot: URL {
        let data = URL(fileURLWithPath: "/System/Volumes/Data")
        return FileManager.default.fileExists(atPath: data.path) ? data : URL(fileURLWithPath: "/")
    }
}
