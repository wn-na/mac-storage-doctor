import AppKit
import SwiftUI
import StorageCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var volume: Volume?
    @Published var volumes: [Volume] = []
    @Published var report: ScanReport?
    @Published var history: [ScanReport] = []
    @Published var cleanupHistory: [CleanupRecord] = []
    @Published var scanning = false
    @Published var paused = false
    @Published var progress = "검사를 시작하면 실제 측정 결과가 표시됩니다."
    @Published var error: String?
    @Published var preview: CleanupPreview?
    @Published var working = false
    @Published var installations: [ToolInstallation] = []
    @Published var assets: [MobileAsset] = []
    @Published var diagnostics = "조회 버튼을 눌러 현재 시스템 상태를 확인하세요."
    @Published var keepWarm: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "keepWarm") ?? [])
    @Published var selectedExternal: Set<String> = []
    @Published var exclusions = UserDefaults.standard.string(forKey: "exclusions") ?? ""
    @Published var automatic = UserDefaults.standard.bool(forKey: "automatic")
    @Published var warningGB = max(1, UserDefaults.standard.integer(forKey: "warningGB") == 0 ? 50 : UserDefaults.standard.integer(forKey: "warningGB"))
    @Published var menuBarDisplay = MenuBarDisplay(rawValue: UserDefaults.standard.string(forKey: "menuBarDisplay") ?? "") ?? .available {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: "menuBarDisplay") }
    }
    @Published var loginEnabled = false
    @Published var loginStatus = ""
    var menuBarLabel: String { MenuBarSummary.label(volume: volume, display: menuBarDisplay) }
    var lowSpace: Bool { MenuBarSummary.isLow(volume: volume, warningGB: warningGB) }
    @Published var monitoring = UserDefaults.standard.object(forKey: "monitoring") as? Bool ?? true
    @Published var monitoringStatus = "전체 분석 후 변경 감시 시작"
    @Published var requiresFullRescan = false
    private let watcher = FSEventWatcher()
    private var watcherGeneration = UUID()
    private var watchedRoots: [URL] = []
    private var pendingEvents: [DirectoryEvent] = []
    private var debounceTask: Task<Void, Never>?
    let cleaner = CleanupEngine()
    private var repository: SnapshotRepository?
    private var scanTask: Task<Void, Never>?
    private var control = ScanControl()
    private var lastAutoScan = Date.distantPast

    init() {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            repository = try SnapshotRepository(url: dir.appendingPathComponent("MacStorageDoctor/history.sqlite"))
        } catch { self.error = error.localizedDescription }
        refreshCapacity()
        Task {
            await reloadHistory()
            do { report = try await repository?.load(ScanReport.self, kind: "index", limit: 1).first ?? history.first }
            catch { self.error = error.localizedDescription; report = history.first }
            if report != nil {
                requiresFullRescan = true
                monitoringStatus = "재시작 이후 변경 확인을 위해 전체 분석 필요"
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                refreshCapacity()
                if automatic && !scanning && !working && Date().timeIntervalSince(lastAutoScan) >= 86400 && ProcessInfo.processInfo.thermalState == .nominal {
                    scan(quick: true)
                }
            }
        }
    }
    func refreshCapacity() {
        volume = try? VolumeInventory.read(VolumeInventory.dataRoot); volumes = VolumeInventory.mounted()
        refreshLoginStatus()
    }
    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        switch status {
        case .enabled: loginStatus = "로그인 시 메뉴바에서 자동 실행됩니다."
        case .requiresApproval: loginStatus = "시스템 설정 > 로그인 항목에서 승인이 필요합니다."
        case .notRegistered: loginStatus = "로그인 자동 실행 꺼짐"
        case .notFound: loginStatus = "Applications에 설치한 앱에서 설정하세요."
        @unknown default: loginStatus = "로그인 항목 상태를 확인할 수 없습니다."
        }
    }
    func setLoginEnabled(_ enabled: Bool) {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            error = "PKG로 Applications에 설치한 앱에서 로그인 자동 실행을 설정하세요."
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { self.error = error.localizedDescription }
        refreshLoginStatus()
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func persistSettings() {
        UserDefaults.standard.set(exclusions, forKey: "exclusions")
        UserDefaults.standard.set(automatic, forKey: "automatic")
        UserDefaults.standard.set(warningGB, forKey: "warningGB")
        UserDefaults.standard.set(monitoring, forKey: "monitoring")
        watcher.stop(); watcherGeneration = UUID()
        pendingEvents = []; debounceTask?.cancel(); debounceTask = nil
        requiresFullRescan = report != nil
        monitoringStatus = monitoring ? "설정 변경: 전체 분석 후 감시 재시작" : "변경 감시 꺼짐"
    }
    func toggleWarm(_ project: Project) {
        if keepWarm.contains(project.id) { keepWarm.remove(project.id) } else { keepWarm.insert(project.id) }
        UserDefaults.standard.set(Array(keepWarm), forKey: "keepWarm")
    }
    private var excludedPaths: [String] {
        exclusions.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        + ["Library/Mobile Documents", "Library/CloudStorage"].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0).path }
    }
    func scan(quick: Bool = false) {
        guard !scanning && !working else { return }
        let roots = [VolumeInventory.dataRoot] + volumes.filter { selectedExternal.contains($0.id) && $0.local }.map(\.url)
        if !quick { startWatching(roots: roots) }
        lastAutoScan = Date()
        performScan(ScanOptions(roots: quick ? [] : roots, exclusions: excludedPaths, quick: quick), incremental: false)
    }
    private func startWatching(roots: [URL]) {
        watcher.stop(); watcherGeneration = UUID(); watchedRoots = roots
        debounceTask?.cancel(); debounceTask = nil; pendingEvents = []; requiresFullRescan = false
        guard monitoring else { monitoringStatus = "변경 감시 꺼짐"; return }
        let generation = watcherGeneration
        do {
            // Start before the full crawl, so changes during the baseline scan are queued.
            try watcher.start(roots: roots) { [weak self] events in
                Task { @MainActor in
                    guard let self, self.watcherGeneration == generation else { return }
                    self.receive(events)
                }
            }
            monitoringStatus = "FSEvents 변경 감시 중"
        } catch { self.error = error.localizedDescription; requireRecovery("변경 감시 시작 실패") }
    }
    private func requireRecovery(_ reason: String) {
        requiresFullRescan = true; pendingEvents = []
        debounceTask?.cancel(); debounceTask = nil
        monitoringStatus = reason + " · 전체 분석 필요"
    }
    private func receive(_ incoming: [DirectoryEvent]) {
        guard monitoring, !requiresFullRescan else { return }
        let events = incoming.filter { IncrementalDiscovery.relevant($0, exclusions: excludedPaths) }
        if events.contains(where: \.requiresFullScan) || pendingEvents.count + events.count > 1024 {
            requireRecovery("이벤트 유실·대량 변경 또는 볼륨 변경 감지"); return
        }
        pendingEvents += events
        schedulePending()
    }
    private func schedulePending() {
        guard monitoring, !requiresFullRescan, !pendingEvents.isEmpty, debounceTask == nil else { return }
        debounceTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            debounceTask = nil
            guard !scanning && !working else { schedulePending(); return }
            guard let baseline = report else { return }
            let events = pendingEvents; pendingEvents = []
            let plan = IncrementalDiscovery.plan(events: events, projects: baseline.projects, watchedRoots: watchedRoots, exclusions: excludedPaths)
            if plan.requiresFullScan { requireRecovery("대량 변경 감지"); return }
            guard !plan.roots.isEmpty else { return }
            performScan(ScanOptions(roots: plan.roots, exclusions: excludedPaths, includeInventory: false), incremental: true)
        }
    }
    private func performScan(_ options: ScanOptions, incremental: Bool) {
        scanning = true; paused = false; control = ScanControl()
        progress = incremental ? "변경된 폴더를 재검사하는 중…" : options.quick ? "알려진 공용 캐시를 측정하는 중…" : "내부 데이터 볼륨에서 프로젝트 탐색 중…"
        let currentControl = control
        let baseline = report
        scanTask = Task {
            let worker = Task.detached(priority: .utility) {
                await Scanner.scan(options, control: currentControl) { count, path in
                    await MainActor.run { self.progress = "\(count.formatted())개 폴더 확인 · \(path)" }
                }
            }
            var result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            if incremental { result.mode = "증분 분석" }
            if let baseline, incremental || (result.cancelled && !options.quick) { report = IncrementalDiscovery.merge(baseline, delta: result) }
            else if let baseline, options.quick { report = IncrementalDiscovery.mergeQuick(baseline, quick: result) }
            else { report = result }
            if result.cancelled && !options.quick { requireRecovery("검사 취소로 변경 반영 중단") }
            progress = result.cancelled ? "검사 취소 · 일부 결과 저장" : "\(result.directories.formatted())개 폴더 검사 · \(result.isPartial ? "부분 검사" : "선택 범위 검사 완료")"
            do {
                try await repository?.save(result, kind: "scan", id: result.id.uuidString)
                if let report { try await repository?.save(report, kind: "index", id: "current-index") }
            } catch { self.error = error.localizedDescription; requireRecovery("검사 결과 저장 실패") }
            scanning = false; paused = false; scanTask = nil
            refreshCapacity(); await reloadHistory(); schedulePending()
        }
    }
    func shutdown() {
        watcher.stop(); watcherGeneration = UUID(); debounceTask?.cancel(); cancel()
    }
    func cancel() { scanTask?.cancel(); control.setPaused(false) }
    func togglePause() { paused.toggle(); control.setPaused(paused) }
    func prepare(_ artifact: Artifact) {
        guard !working && !scanning else { return }; working = true
        Task {
            defer { working = false }
            do { preview = try await cleaner.preview(artifact, keepWarm: keepWarm) } catch { self.error = error.localizedDescription }
        }
    }
    func clean(_ approved: CleanupPreview) {
        guard !working && !scanning else { return }; working = true; preview = nil
        Task {
            defer { working = false }
            do {
                let record = try await cleaner.execute(approved, keepWarm: keepWarm)
                // Keep the visible result even if persistent storage fails.
                cleanupHistory.insert(record, at: 0)
                report?.artifacts.removeAll { $0.id == approved.artifact.id }
                if let report { try await repository?.save(report, kind: "index", id: "current-index") }
                try await repository?.save(record, kind: "cleanup", id: record.id.uuidString)
                refreshCapacity()
            } catch { self.error = error.localizedDescription }
        }
    }
    func reloadHistory() async {
        do {
            history = try await repository?.load(ScanReport.self, kind: "scan", limit: 30) ?? []
            cleanupHistory = try await repository?.load(CleanupRecord.self, kind: "cleanup") ?? []
        } catch { self.error = error.localizedDescription }
    }
    func inspectToolchains() {
        guard !working else { return }; working = true
        Task {
            installations = await Task.detached(priority: .utility) { ToolchainInspector.installations() }.value
            diagnostics = ToolchainInspector.ndkRequirements(projects: report?.projects ?? [], installations: installations)
            working = false
        }
    }
    func inspectAssets() {
        guard !working else { return }; working = true
        Task {
            assets = await Task.detached(priority: .utility) { MobileAssetInspector.scan() }.value
            diagnostics = assets.isEmpty ? "읽을 수 있는 Simulator MobileAsset을 찾지 못했습니다. 없음과 권한 부족을 구분하려면 전체 검사 누락 기록을 확인하세요." : "MobileAsset 메타데이터입니다. 런타임 등록 및 시스템 참조 여부는 확정하지 않으며 직접 삭제하지 않습니다."
            working = false
        }
    }
    func diagnose(snapshots: Bool) {
        guard !working else { return }; working = true; diagnostics = "공식 도구로 읽기 전용 조회 중…"
        Task {
            diagnostics = await Task.detached(priority: .utility) { snapshots ? Diagnostics.snapshots() : Diagnostics.simulators() }.value
            working = false
        }
    }
    func export() {
        guard let report else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "storage-diagnosis.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Diagnostics.maskedReport(report).write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
    }
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
