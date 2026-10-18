import AppKit
import SwiftUI
import StorageCore

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
            report = history.first
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                refreshCapacity()
                if automatic && !scanning && !working && Date().timeIntervalSince(lastAutoScan) >= 86400 && ProcessInfo.processInfo.thermalState == .nominal {
                    scan(quick: true)
                }
            }
        }
    }
    func refreshCapacity() { volume = try? VolumeInventory.read(VolumeInventory.dataRoot); volumes = VolumeInventory.mounted() }
    func persistSettings() {
        UserDefaults.standard.set(exclusions, forKey: "exclusions")
        UserDefaults.standard.set(automatic, forKey: "automatic")
        UserDefaults.standard.set(warningGB, forKey: "warningGB")
    }
    func toggleWarm(_ project: Project) {
        if keepWarm.contains(project.id) { keepWarm.remove(project.id) } else { keepWarm.insert(project.id) }
        UserDefaults.standard.set(Array(keepWarm), forKey: "keepWarm")
    }
    func scan(quick: Bool = false) {
        guard !scanning && !working else { return }
        scanning = true; paused = false; control = ScanControl(); lastAutoScan = Date()
        progress = quick ? "알려진 공용 캐시를 측정하는 중…" : "내부 데이터 볼륨에서 프로젝트 탐색 중…"
        let options = ScanOptions(roots: quick ? [] : [VolumeInventory.dataRoot] + volumes.filter { selectedExternal.contains($0.id) && $0.local }.map(\.url), exclusions: exclusions.split(separator: "\n").map(String.init), quick: quick)
        let currentControl = control
        scanTask = Task {
            let worker = Task.detached(priority: .utility) {
                await Scanner.scan(options, control: currentControl) { count, path in
                    await MainActor.run { self.progress = "\(count.formatted())개 폴더 확인 · \(path)" }
                }
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            report = result
            progress = result.cancelled ? "검사 취소 · 일부 결과 저장" : "\(result.directories.formatted())개 폴더 검사 · \(result.isPartial ? "부분 검사" : "선택 범위 검사 완료")"
            do { try await repository?.save(result, kind: "scan", id: result.id.uuidString) } catch { self.error = error.localizedDescription }
            scanning = false; paused = false; scanTask = nil
            refreshCapacity(); await reloadHistory()
        }
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
