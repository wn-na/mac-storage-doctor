import Observation
import AppKit
import SwiftUI
import StorageCore
import ServiceManagement

struct BatchCleanupPreview: Identifiable {
    let id = UUID()
    let items: [CleanupPreview]
    let skipped: [String]
}

@MainActor
@Observable
final class AppModel {
    var volume: Volume?
    var volumes: [Volume] = []
    var capacityPoints: [CapacityPoint] = []
    var capacityError: String?
    var capacityRange: CapacityRange = .month {
        didSet { updateCapacityHistory() }
    }
    private var capacityRequest = UUID()
    private var capacityRefreshInFlight = false
    private var capacityChartSubscribers = 0
    private var progressLastPublished = Date.distantPast
    var report: ScanReport?
    var history: [ScanSummary] = []
    var cleanupHistory: [CleanupRecord] = []
    var scanning = false
    var paused = false
    var progress = "검사를 시작하면 실제 측정 결과가 표시됩니다."
    var error: String?
    var preview: CleanupPreview?
    var batchPreview: BatchCleanupPreview?
    var simulatorBatch: SimulatorCleanupBatch?
    var selectedDevices: Set<String> = []
    var managedPreview: ManagedRemovalPreview?
    var developerInventory = DeveloperInventory()
    var developerLoaded = false
    var developerSizesRequested = false
    var selectedArtifacts = Set<String>()
    var cleanupSummary: String?
    var tutorialPresented = !UserDefaults.standard.bool(forKey: "tutorialCompleted")
    var incrementalMinutes = max(5, UserDefaults.standard.integer(forKey: "incrementalMinutes") == 0 ? 30 : UserDefaults.standard.integer(forKey: "incrementalMinutes"))
    private let developerActions = DeveloperActions()
    private var lastIncremental = Date.distantPast
    var hasApproval: Bool { preview != nil || batchPreview != nil || managedPreview != nil || simulatorBatch != nil }
    var selectedItems: [Artifact] { (report?.artifacts ?? []).filter { selectedArtifacts.contains($0.id) && $0.canTrash } }
    var quickItems: [Artifact] { (report?.artifacts ?? []).filter { $0.quickEligible && !keepWarm.contains($0.projectID ?? "") } }
    var working = false
    var installations: [ToolInstallation] = []
    var assets: [MobileAsset] = []
    var diagnostics = "조회 버튼을 눌러 현재 시스템 상태를 확인하세요."
    var keepWarm: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "keepWarm") ?? [])
    var selectedExternal: Set<String> = []
    var exclusions = UserDefaults.standard.string(forKey: "exclusions") ?? ""
    var automatic = UserDefaults.standard.bool(forKey: "automatic")
    var warningGB = max(1, UserDefaults.standard.integer(forKey: "warningGB") == 0 ? 50 : UserDefaults.standard.integer(forKey: "warningGB"))
    var menuBarDisplay = MenuBarDisplay(rawValue: UserDefaults.standard.string(forKey: "menuBarDisplay") ?? "") ?? .available {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: "menuBarDisplay") }
    }
    var loginEnabled = false
    var loginStatus = ""
    var menuBarLabel: String { MenuBarSummary.label(volume: volume, display: menuBarDisplay) }
    var lowSpace: Bool { MenuBarSummary.isLow(volume: volume, warningGB: warningGB) }
    var monitoring = UserDefaults.standard.object(forKey: "monitoring") as? Bool ?? false
    var monitoringStatus = "전체 분석 후 변경 감시 시작"
    var requiresFullRescan = false
    private let watcher = FSEventWatcher()
    private var watcherGeneration = UUID()
    private var watchedRoots: [URL] = []
    private var pendingEvents: [DirectoryEvent] = []
    private var debounceTask: Task<Void, Never>?
    let cleaner = CleanupEngine()
    private var repository: SnapshotRepository?
    private var scanTask: Task<Void, Never>?
    private var control = ScanControl()
    private var lastAutoScan = UserDefaults.standard.object(forKey: "lastAutoScan") as? Date ?? Date()

    init() {
        // Migrate the formerly eager defaults once; later explicit choices are respected.
        if !UserDefaults.standard.bool(forKey: "manualAnalysisDefaultV2") {
            automatic = false; monitoring = false
            UserDefaults.standard.set(false, forKey: "automatic")
            UserDefaults.standard.set(false, forKey: "monitoring")
            UserDefaults.standard.set(true, forKey: "manualAnalysisDefaultV2")
        }
        Task {
            do {
                repository = try await Task.detached(priority: .utility) {
                    let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    return try SnapshotRepository(url: dir.appendingPathComponent("MacStorageDoctor/history.sqlite"))
                }.value
                var loaded = try await repository?.load(ScanReport.self, kind: "index", limit: 1).first
                if loaded == nil { loaded = try await repository?.load(ScanReport.self, kind: "scan", limit: 1).first }
                if let loaded { report = await Task.detached(priority: .utility) { CleanupCatalog.upgrade(loaded) }.value }
            } catch { self.error = error.localizedDescription }
            refreshLoginStatus()
            refreshCapacity()
            await reloadHistory()
            if report != nil {
                requiresFullRescan = true
                monitoringStatus = "재시작 이후 변경 확인을 위해 전체 분석 필요"
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                refreshCapacity()
                if automatic && !scanning && !working && !hasApproval && AnalysisSchedule.due(last: lastAutoScan, intervalHours: 24) && ProcessInfo.processInfo.thermalState == .nominal {
                    scan(quick: true)
                }
            }
        }
    }
    func refreshCapacity() {
        guard !capacityRefreshInFlight else { return }
        capacityRefreshInFlight = true
        Task {
            defer { capacityRefreshInFlight = false }
            let snapshot = await Task.detached(priority: .utility) {
                (try? VolumeInventory.read(VolumeInventory.dataRoot), VolumeInventory.mounted())
            }.value
            if volume != snapshot.0 { volume = snapshot.0 }
            if volumes != snapshot.1 { volumes = snapshot.1 }
            updateCapacityHistory(record: true)
        }
    }
    func observeCapacityHistory(_ visible: Bool) {
        capacityChartSubscribers = max(0, capacityChartSubscribers + (visible ? 1 : -1))
        if visible { updateCapacityHistory() }
    }
    private func updateCapacityHistory(record: Bool = false) {
        let request = UUID(); capacityRequest = request
        guard let volume else {
            capacityPoints = []; capacityError = "현재 볼륨 용량을 읽을 수 없습니다."
            return
        }
        let range = capacityRange
        Task {
            do {
                guard let repository else { throw RepositoryError.failure("이력 저장소를 열 수 없습니다.") }
                if record { try await repository.recordCapacity(volume) }
                guard capacityChartSubscribers > 0 else { return }
                let points = try await repository.capacity(volumeID: volume.id, since: range.start())
                let aggregated = await Task.detached(priority: .utility) {
                    CapacityHistory.aggregate(points, resolution: range.resolution)
                }.value
                guard capacityRequest == request else { return }
                capacityPoints = aggregated; capacityError = nil
            } catch {
                guard capacityRequest == request else { return }
                capacityPoints = []; capacityError = "용량 이력 저장·조회 실패: " + error.localizedDescription
            }
        }
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
        UserDefaults.standard.set(incrementalMinutes, forKey: "incrementalMinutes")
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
        guard !scanning && !working && !hasApproval else { return }
        let roots = [VolumeInventory.dataRoot] + volumes.filter { selectedExternal.contains($0.id) && $0.local }.map(\.url)
        if !quick { startWatching(roots: roots) }
        lastAutoScan = Date()
        UserDefaults.standard.set(lastAutoScan, forKey: "lastAutoScan")
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
            do { try await Task.sleep(for: .seconds(AnalysisSchedule.delay(lastIncremental: lastIncremental, minutes: incrementalMinutes))) } catch { return }
            debounceTask = nil
            guard !scanning && !working && !hasApproval else { schedulePending(); return }
            guard let baseline = report else { return }
            let events = pendingEvents; pendingEvents = []
            let plan = IncrementalDiscovery.plan(events: events, projects: baseline.projects, watchedRoots: watchedRoots, exclusions: excludedPaths)
            if plan.requiresFullScan { requireRecovery("대량 변경 감지"); return }
            guard !plan.roots.isEmpty else { return }
            lastIncremental = Date()
            performScan(ScanOptions(roots: plan.roots, exclusions: excludedPaths, includeInventory: false), incremental: true)
        }
    }
    private func performScan(_ options: ScanOptions, incremental: Bool) {
        lastIncremental = Date()
        scanning = true; paused = false; control = ScanControl()
        progress = incremental ? "변경된 폴더를 재검사하는 중…" : options.quick ? "알려진 공용 캐시를 측정하는 중…" : "내부 데이터 볼륨에서 프로젝트 탐색 중…"
        let currentControl = control
        let baseline = report
        scanTask = Task {
            let worker = Task.detached(priority: .utility) {
                await Scanner.scan(options, control: currentControl) { count, path in
                    await MainActor.run {
                        if Date().timeIntervalSince(self.progressLastPublished) >= 0.25 {
                            self.progressLastPublished = Date()
                            self.progress = "\(count.formatted())개 폴더 확인 · \(path)"
                        }
                    }
                }
            }
            var result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            if incremental { result.mode = "증분 분석" }
            let completed = result
            report = await Task.detached(priority: .utility) {
                let merged: ScanReport
                if let baseline, incremental || (completed.cancelled && !options.quick) { merged = IncrementalDiscovery.merge(baseline, delta: completed) }
                else if let baseline, options.quick { merged = IncrementalDiscovery.mergeQuick(baseline, quick: completed) }
                else { merged = completed }
                return CleanupCatalog.upgrade(merged)
            }.value
            if result.cancelled && !options.quick { requireRecovery("검사 취소로 변경 반영 중단") }
            progress = result.cancelled ? "검사 취소 · 일부 결과 저장" : "\(result.directories.formatted())개 폴더 검사 · \(result.isPartial ? "부분 검사" : "선택 범위 검사 완료")"
            do {
                try await repository?.save(result, kind: "scan", id: result.id.uuidString)
                if let report { try await repository?.save(report, kind: "index", id: "current-index") }
            } catch { self.error = error.localizedDescription; requireRecovery("검사 결과 저장 실패") }
            scanning = false; paused = false; scanTask = nil
            selectedArtifacts.formIntersection(Set((report?.artifacts ?? []).map(\.id)))
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
            let record: CleanupRecord
            do {
                record = try await cleaner.execute(approved, keepWarm: keepWarm)
                report?.artifacts.removeAll { $0.id == approved.artifact.id }
            } catch {
                record = .failed(path: approved.artifact.url.path, reason: error.localizedDescription)
                self.error = error.localizedDescription
            }
            // Show the operation outcome even when writing its audit record fails.
            cleanupHistory.insert(record, at: 0)
            do {
                guard let repository else { throw RepositoryError.failure("이력 저장소를 열 수 없습니다.") }
                try await repository.save(record, kind: "cleanup", id: record.id.uuidString)
            }
            catch { self.error = record.status + " · 이력 저장 실패: " + error.localizedDescription }
            if record.failureReason == nil, let report {
                do { try await repository?.save(report, kind: "index", id: "current-index") }
                catch { self.error = "정리는 완료했으나 검사 인덱스 저장에 실패했습니다: " + error.localizedDescription }
            }
            refreshCapacity()
        }
    }
    func finishTutorial() {
        UserDefaults.standard.set(true, forKey: "tutorialCompleted")
        tutorialPresented = false
    }
    func prepareBatch(quick: Bool = false) {
        guard !working && !scanning && !hasApproval else { return }
        let items = quick ? quickItems : selectedItems
        guard !items.isEmpty else { error = "정리 가능한 항목이 없습니다. 분석 후 정리할 항목을 선택하세요."; return }
        working = true; cleanupSummary = "선택 항목의 변경·보호 상태를 확인하는 중…"
        Task {
            defer { working = false }
            var previews: [CleanupPreview] = [], skipped: [String] = []
            for artifact in items {
                do { previews.append(try await cleaner.preview(artifact, keepWarm: keepWarm)) }
                catch { skipped.append(artifact.owner + " / " + artifact.url.lastPathComponent + ": " + error.localizedDescription) }
            }
            batchPreview = BatchCleanupPreview(items: previews, skipped: skipped)
            cleanupSummary = nil
        }
    }
    private func recordCleanup(_ record: CleanupRecord) async {
        cleanupHistory.insert(record, at: 0)
        do {
            guard let repository else { throw RepositoryError.failure("이력 저장소 없음") }
            try await repository.save(record, kind: "cleanup", id: record.id.uuidString)
        } catch { self.error = "작업 결과: " + record.status + " · 이력 저장 실패: " + error.localizedDescription }
    }
    func cleanBatch(_ batch: BatchCleanupPreview) {
        guard !working && !scanning else { return }
        batchPreview = nil; working = true
        Task {
            defer { working = false }
            var success = 0, failed = 0
            for (index, item) in batch.items.enumerated() {
                cleanupSummary = "정리 중 \(index + 1)/\(batch.items.count) · \(item.artifact.owner)"
                let record: CleanupRecord
                do {
                    record = try await cleaner.execute(item, keepWarm: keepWarm)
                    report?.artifacts.removeAll { $0.id == item.artifact.id }
                    selectedArtifacts.remove(item.artifact.id); success += 1
                } catch { record = .failed(path: item.artifact.url.path, reason: error.localizedDescription); failed += 1 }
                await recordCleanup(record)
            }
            if let report {
                do { try await repository?.save(report, kind: "index", id: "current-index") }
                catch { self.error = "정리 결과 인덱스 저장 실패: " + error.localizedDescription }
            }
            cleanupSummary = "휴지통 이동 \(success)개 · 실패 \(failed)개 · 사전 검사 제외 \(batch.skipped.count)개. 공간 회수는 휴지통을 비운 뒤 반영됩니다."
            refreshCapacity()
        }
    }
    func refreshDeveloperInventory(measureSizes: Bool = false) {
        guard !working && !scanning && !hasApproval else { return }; working = true
        Task {
            developerInventory = await Task.detached(priority: .utility) { DeveloperManager.inventory(measureSizes: measureSizes) }.value
            developerSizesRequested = measureSizes
            developerLoaded = true; working = false
        }
    }
    func prepareSDK(_ package: SDKPackage) {
        guard !working && !scanning && !hasApproval else { return }; working = true
        Task {
            defer { working = false }
            do { managedPreview = try await developerActions.preview(sdk: package, projects: report?.projects ?? [], keepWarm: keepWarm) }
            catch { self.error = error.localizedDescription }
        }
    }
    func prepareDevice(_ device: SimulatorDevice) {
        guard !working && !scanning && !hasApproval else { return }; working = true
        Task {
            defer { working = false }
            do { managedPreview = try await developerActions.preview(device: device) }
            catch { self.error = error.localizedDescription }
        }
    }
    func prepareSimulatorCleanup(_ action: SimulatorCleanupAction) {
        guard !working && !scanning && !hasApproval else { return }
        let devices = developerInventory.devices.filter { selectedDevices.contains($0.id) }
        working = true
        Task {
            defer { working = false }
            do { simulatorBatch = try await developerActions.preview(devices: devices, action: action) }
            catch { self.error = error.localizedDescription }
        }
    }
    func cleanSimulators(_ batch: SimulatorCleanupBatch) {
        guard !working && !scanning, simulatorBatch?.id == batch.id else { return }
        working = true; simulatorBatch = nil
        Task {
            var succeeded = 0, failed = 0
            for (index, item) in batch.items.enumerated() {
                cleanupSummary = "\(batch.action.title) 중 \(index + 1)/\(batch.items.count) · \(item.title)"
                let record: CleanupRecord
                do {
                    record = try await developerActions.execute(item, keepWarm: keepWarm, projects: report?.projects ?? [])
                    succeeded += 1
                    if let device = item.device { selectedDevices.remove(device.id) }
                } catch {
                    record = .failed(path: item.device?.udid ?? item.title, reason: error.localizedDescription)
                    failed += 1
                }
                await recordCleanup(record)
            }
            developerInventory = await Task.detached(priority: .utility) { DeveloperManager.inventory() }.value
            selectedDevices.formIntersection(Set(developerInventory.devices.map(\.id)))
            developerSizesRequested = false
            cleanupSummary = "\(batch.action.title) 완료 \(succeeded)개 · 실패 \(failed)개. 상세 결과는 기록에서 확인하세요. 공용 런타임은 유지됩니다."
            working = false; refreshCapacity()
        }
    }
    func removeManaged(_ approved: ManagedRemovalPreview) {
        guard !working && !scanning else { return }; working = true; managedPreview = nil
        Task {
            let record: CleanupRecord
            do { record = try await developerActions.execute(approved, keepWarm: keepWarm, projects: report?.projects ?? []) }
            catch { record = .failed(path: approved.sdk?.location.path ?? approved.device?.udid ?? approved.title, reason: error.localizedDescription); self.error = error.localizedDescription }
            await recordCleanup(record)
            developerInventory = await Task.detached(priority: .utility) { DeveloperManager.inventory() }.value
            developerSizesRequested = false
            cleanupSummary = record.status
            working = false; refreshCapacity()
        }
    }
    func reloadHistory() async {
        do {
            history = try await repository?.scanSummaries() ?? []
            cleanupHistory = try await repository?.load(CleanupRecord.self, kind: "cleanup") ?? []
        } catch { self.error = error.localizedDescription }
    }
    func inspectToolchains() {
        guard !working else { return }; working = true
        Task {
            let projects = report?.projects ?? []
            let inspected = await Task.detached(priority: .utility) {
                let installations = ToolchainInspector.installations()
                return (installations, ToolchainInspector.ndkRequirements(projects: projects, installations: installations))
            }.value
            installations = inspected.0; diagnostics = inspected.1
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
