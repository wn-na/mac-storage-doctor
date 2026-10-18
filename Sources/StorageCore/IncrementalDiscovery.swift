import Foundation
import CoreServices

public struct DirectoryEvent: Sendable {
    public var path: String
    public var flags: UInt32
    public init(path: String, flags: UInt32) { self.path = path; self.flags = flags }
    public var requiresFullScan: Bool {
        let mask = kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagUnmount | kFSEventStreamEventFlagMount
        return flags & UInt32(mask) != 0
    }
}
public struct RescanPlan: Sendable {
    public var roots: [URL] = []
    public var requiresFullScan = false
}
public enum IncrementalDiscovery {
    public static func normalizedPath(_ path: String) -> String {
        let prefix = "/System/Volumes/Data"
        if path == prefix { return "/" }
        return path.hasPrefix(prefix + "/") ? String(path.dropFirst(prefix.count)) : path
    }
    public static func contains(_ parent: String, _ path: String) -> Bool {
        let parent = normalizedPath(parent), path = normalizedPath(path)
        return parent == "/" || parent == path || path.hasPrefix(parent + "/")
    }
    public static func compact(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.path.count < $1.path.count }.reduce(into: []) { roots, url in
            if !roots.contains(where: { contains($0.path, url.path) }) { roots.append(url) }
        }
    }
    public static func relevant(_ event: DirectoryEvent, exclusions: [String]) -> Bool {
        if event.requiresFullScan { return true }
        let url = URL(fileURLWithPath: normalizedPath(event.path))
        let generated: Set<String> = ["node_modules", ".git", ".gradle", ".build", ".dart_tool", "Pods", "DerivedData", ".Trash"]
        let signatures: Set<String> = ["package.json", "pubspec.yaml", "Package.swift", "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts", "gradlew", "project.pbxproj"]
        guard !url.pathComponents.contains(where: { generated.contains($0) || $0.hasSuffix(".app") }),
              !exclusions.contains(where: { contains($0, url.path) }) else { return false }
        let directoryChange = event.flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 && event.flags & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed) != 0
        return signatures.contains(url.lastPathComponent) || url.pathExtension == "xcodeproj" || directoryChange || event.flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0
    }
    public static func plan(events: [DirectoryEvent], projects: [Project], watchedRoots: [URL], exclusions: [String]) -> RescanPlan {
        var plan = RescanPlan()
        if events.contains(where: \.requiresFullScan) || events.count > 1024 { plan.requiresFullScan = true; return plan }
        for event in events {
            let url = URL(fileURLWithPath: normalizedPath(event.path))
            guard relevant(event, exclusions: exclusions) else { continue }
            let isDirectory = event.flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            var candidate = isDirectory ? url : url.deletingLastPathComponent()
            if candidate.pathExtension == "xcodeproj" { candidate.deleteLastPathComponent() }
            // Reclassify the owning workspace, including native folders hidden by grouping.
            if let owner = projects.filter({ contains($0.root.path, candidate.path) }).min(by: { $0.root.path.count < $1.root.path.count }) { candidate = owner.root }
            // Deleted paths must be reconciled by enumerating a surviving ancestor.
            while (try? FileSystem.metadata(candidate)).map(FileSystem.isDirectory) != true && candidate.path != "/" { candidate.deleteLastPathComponent() }
            guard let metadata = try? FileSystem.metadata(candidate), !FileSystem.isLink(metadata),
                  watchedRoots.contains(where: { root in
                      contains(root.path, candidate.path) && (try? FileSystem.metadata(root).st_dev) == metadata.st_dev
                  }), !exclusions.contains(where: { contains($0, candidate.path) }) else { continue }
            plan.roots.append(FileSystem.visibleURL(candidate))
        }
        plan.roots = compact(plan.roots)
        if plan.roots.count > 64 { plan.roots = []; plan.requiresFullScan = true }
        return plan
    }
    public static func merge(_ previous: ScanReport, delta: ScanReport) -> ScanReport {
        var merged = previous
        merged.id = delta.id; merged.startedAt = delta.startedAt; merged.finishedAt = delta.finishedAt
        merged.mode = "증분 분석"; merged.cancelled = delta.cancelled
        func covered(_ path: String) -> Bool {
            !delta.cancelled && delta.roots.contains { contains($0.path, path) } && !delta.issues.contains { contains($0.path, path) }
        }
        let retained = previous.projects.filter { !covered($0.root.path) }
        var byID = Dictionary(retained.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for project in delta.projects { byID[project.id] = project }
        merged.projects = ProjectClassifier.group(Array(byID.values))
        var artifacts = Dictionary(previous.artifacts.filter { !covered($0.url.path) }.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for artifact in delta.artifacts { artifacts[artifact.id] = artifact }
        merged.artifacts = artifacts.values.sorted { $0.id < $1.id }
        merged.issues = (previous.issues.filter { !covered($0.path) } + delta.issues).reduce(into: []) { issues, issue in
            if !issues.contains(where: { $0.id == issue.id }) { issues.append(issue) }
        }
        return merged
    }
    public static func mergeQuick(_ previous: ScanReport, quick: ScanReport) -> ScanReport {
        var merged = previous
        merged.id = quick.id; merged.startedAt = quick.startedAt; merged.finishedAt = quick.finishedAt
        merged.mode = "빠른 분석 · 프로젝트는 이전 결과"; merged.cancelled = quick.cancelled
        var artifacts = Dictionary(previous.artifacts.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for artifact in quick.artifacts { artifacts[artifact.id] = artifact }
        merged.artifacts = artifacts.values.sorted { $0.id < $1.id }
        merged.issues += quick.issues
        return merged
    }
}

/// Lifecycle is owned by the main actor; callbacks retain their own immutable context.
@MainActor
public final class FSEventWatcher {
    private final class Context: Sendable {
        let callback: @Sendable ([DirectoryEvent]) -> Void
        init(_ callback: @escaping @Sendable ([DirectoryEvent]) -> Void) { self.callback = callback }
    }
    private var stream: FSEventStreamRef?
    public init() {}
    public func start(roots: [URL], callback: @escaping @Sendable ([DirectoryEvent]) -> Void) throws {
        stop()
        let context = Context(callback)
        var configuration = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(context).toOpaque(), retain: { pointer in
            guard let pointer else { return nil }
            _ = Unmanaged<Context>.fromOpaque(pointer).retain(); return pointer
        }, release: { pointer in
            if let pointer { Unmanaged<Context>.fromOpaque(pointer).release() }
        }, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        guard let created = FSEventStreamCreate(nil, { _, info, count, rawPaths, rawFlags, _ in
            guard let info else { return }
            let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self)
            var events: [DirectoryEvent] = []
            for index in 0..<count {
                if let path = paths[index] as? String { events.append(.init(path: path, flags: rawFlags[index])) }
            }
            context.callback(events)
        }, &configuration, roots.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, FSEventStreamCreateFlags(flags)) else { throw WatchError.unavailable }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created); FSEventStreamRelease(created); throw WatchError.unavailable
        }
        stream = created
    }
    public func stop() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
    }
    public enum WatchError: LocalizedError {
        case unavailable
        public var errorDescription: String? { "FSEvents 감시를 시작할 수 없습니다. 전체 분석으로 확인하세요." }
    }
}
