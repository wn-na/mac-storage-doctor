import SwiftUI
import StorageCore

private enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview", space = "Space Map", caches = "System & App Caches", projects = "Projects", tools = "Toolchains", cleaner = "Smart Cleaner", history = "History", settings = "Settings & Permissions"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .space: "chart.pie"
        case .caches: "externaldrive"
        case .projects: "folder"
        case .tools: "hammer"
        case .cleaner: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        }
    }
}
struct MainView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: Page = .overview
    @State private var search = ""
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "cross.case.fill").font(.title).foregroundStyle(.mint)
                    VStack(alignment: .leading) { Text("STORAGE").font(.headline); Text("DOCTOR").font(.caption).tracking(3).foregroundStyle(.secondary) }
                }.padding(20)
                Text("WORKSPACE").font(.caption2.bold()).foregroundStyle(.secondary).padding(.horizontal, 20)
                ForEach(Page.allCases) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.icon).font(.system(size: 13, weight: page == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(page == item ? Color.mint.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(page == item ? Color.mint : .primary)
                    }.buttonStyle(.plain).padding(.horizontal, 10)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 7) {
                    Label("로컬에서 분석", systemImage: "lock.shield").font(.subheadline.bold())
                    Text("개인 파일을 업로드하지 않습니다.\n정리는 항상 미리보기와 승인 후 실행됩니다.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(235)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(page.rawValue).font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Mac의 공간을 이해하고, 필요한 것만 정리하세요.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.scanning {
                        Button(model.paused ? "계속" : "일시정지") { model.togglePause() }
                        Button("취소") { model.cancel() }
                    } else {
                        Button("빠른 분석") { model.scan(quick: true) }.disabled(model.working)
                        Button { model.scan() } label: { Label("전체 분석", systemImage: "magnifyingglass") }.buttonStyle(.borderedProminent).tint(.mint).disabled(model.working)
                    }
                }.padding(28)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if model.scanning {
                            HStack { ProgressView().controlSize(.small); Text(model.progress).font(.caption).lineLimit(1); Spacer() }.padding().background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        if model.requiresFullRescan {
                            Label(model.monitoringStatus, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.callout).foregroundStyle(.orange)
                        }
                        content
                    }.padding(28)
                }
                HStack {
                    Circle().fill(model.scanning ? .orange : .mint).frame(width: 6, height: 6)
                    Text(model.report?.finishedAt.map { "최근 검사 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "검사 기록 없음")
                    Spacer()
                    Text("macOS 관리 자산은 진단 전용")
                }.font(.caption).foregroundStyle(.secondary).padding(12).background(.quaternary.opacity(0.3))
            }
        }
        .tint(.mint)
        .alert("작업 안내", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("확인") { model.error = nil } } message: { Text(model.error ?? "") }
        .sheet(item: $model.preview) { preview in
            VStack(alignment: .leading, spacing: 18) {
                Label("정리 미리보기", systemImage: "trash").font(.title2.bold())
                Text(preview.artifact.url.path).textSelection(.enabled)
                Text("할당 용량 \(Format.bytes(preview.artifact.measurement.allocated)) · APFS 공유 블록으로 실제 회수량과 다를 수 있습니다.")
                Text(preview.artifact.reason).foregroundStyle(.secondary)
                Text("휴지통으로 이동합니다. 휴지통을 비우기 전에는 공간이 회수되지 않습니다. 앱은 휴지통을 비우지 않습니다.").padding().background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                HStack { Spacer(); Button("취소") { model.preview = nil }; Button("승인하고 휴지통으로 이동") { model.clean(preview) }.buttonStyle(.borderedProminent) }
            }.padding(28).frame(width: 560)
        }
    }
    @ViewBuilder private var content: some View {
        switch page {
        case .overview: overview
        case .space: SpaceExplorer()
        case .projects: projects
        case .caches: inventory(title: "시스템과 앱 데이터를 구분합니다", artifacts: (model.report?.artifacts ?? []).filter { $0.projectID == nil })
        case .tools: tools
        case .cleaner: inventory(title: "정리 전 영향을 확인하세요", artifacts: model.report?.artifacts ?? [])
        case .history: history
        case .settings: settings
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 20) {
                    Label("INTERNAL STORAGE", systemImage: "internaldrive").font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
                    Text(model.volume.map { Format.bytes($0.available) } ?? "—").font(.system(size: 56, weight: .semibold, design: .rounded))
                    Text("사용 가능한 공간").foregroundStyle(.secondary)
                    if let v = model.volume {
                        ProgressView(value: Double(v.used), total: Double(max(1, v.total))).tint(.mint)
                        HStack { Text("사용 중 \(Format.bytes(v.used))"); Spacer(); Text("전체 \(Format.bytes(v.total))") }.font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(26).background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 20) {
                    Label("SCAN STATUS", systemImage: "waveform.path.ecg").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(model.report == nil ? "분석 준비 완료" : (model.report!.isPartial ? "부분 검사" : "선택 범위 검사 완료")).font(.title2.bold())
                    Text("\(model.report?.projects.count ?? 0)개 프로젝트 발견").font(.headline)
                    Text("\(model.report?.issues.count ?? 0)개 제외·누락 기록").foregroundStyle(.secondary)
                    Button("검사 범위 확인") { page = .settings }
                }.frame(width: 225, alignment: .leading).padding(26).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
            }
            if let v = model.volume, v.available < Int64(model.warningGB) * 1_073_741_824 { Label("여유 공간이 설정한 \(model.warningGB) GiB보다 적습니다.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            HStack(spacing: 16) {
                metric("실행 가능한 검토 후보", amount: (model.report?.artifacts ?? []).filter(\.canTrash).reduce(0) { $0 + $1.measurement.allocated }, symbol: "sparkles", color: .mint)
                metric("진단 전용 항목", amount: (model.report?.artifacts ?? []).filter { !$0.canTrash }.reduce(0) { $0 + $1.measurement.allocated }, symbol: "shield.lefthalf.filled", color: .blue)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("숫자를 올바르게 이해하기").font(.headline)
                    Text("macOS ‘시스템 데이터’는 단일 폴더가 아닙니다. 아래 측정값은 앱이 접근한 파일의 할당 용량이며 Apple의 저장 공간 분류와 같지 않습니다. APFS 복제본·스냅샷·권한 누락 때문에 파일 합계와 볼륨 사용량은 다를 수 있습니다.").foregroundStyle(.secondary)
                    Text("빠른 분석은 알려진 캐시만 측정합니다. 전체 분석은 내부 데이터 볼륨에서 프로젝트를 탐색하며 숨김 폴더도 포함합니다.").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            CapacityHistoryView()
            Text("큰 항목").font(.title3.bold())
            ForEach(Array((model.report?.artifacts ?? []).sorted { $0.measurement.allocated > $1.measurement.allocated }.prefix(5))) { artifact in artifactRow(artifact) }
            if model.report == nil { empty("첫 번째 분석을 시작하세요", subtitle: "예시 숫자 대신 현재 Mac의 실제 측정값을 표시합니다.") }
        }
    }
    private func metric(_ title: String, amount: Int64, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) { Label(title, systemImage: symbol).foregroundStyle(color); Text(Format.bytes(amount)).font(.title.bold()); Text("측정된 할당 용량 · 회수 보장 아님").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }
    private var projects: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("프로젝트 이름 또는 경로 검색", text: $search).textFieldStyle(.roundedBorder)
            ForEach((model.report?.projects ?? []).filter { search.isEmpty || $0.root.path.localizedCaseInsensitiveContains(search) }) { project in
                HStack {
                    Image(systemName: "folder.fill").font(.title).foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(project.name).font(.headline)
                        Text(project.platforms.map(\.rawValue).sorted().joined(separator: " · ")).foregroundStyle(.mint)
                        Text(project.root.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(project.evidence.joined(separator: " / ")).font(.caption2).foregroundStyle(.secondary)
                        if let parent = project.workspace { Text("상위 워크스페이스: \(parent)").font(.caption2) }
                    }
                    Spacer()
                    Toggle("Keep Warm", isOn: Binding(get: { model.keepWarm.contains(project.id) }, set: { _ in model.toggleWarm(project) })).toggleStyle(.switch).fixedSize()
                    Button { model.reveal(project.root) } label: { Image(systemName: "arrow.up.forward.square") }
                }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            if model.report?.projects.isEmpty != false { empty("발견된 프로젝트 없음", subtitle: "전체 분석으로 로컬 볼륨을 검사하세요. 빠른 분석은 기존 프로젝트 결과를 유지합니다.") }
        }
    }
    private func inventory(title: String, artifacts: [Artifact]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.bold())
            Text("현재 직접 실행은 검증된 Xcode DerivedData의 휴지통 이동을 지원합니다. 다른 캐시·SDK는 진단과 공식 관리 안내를 제공합니다.").foregroundStyle(.secondary)
            ForEach(Risk.allCases, id: \.self) { risk in
                let items = artifacts.filter { $0.risk == risk }
                if !items.isEmpty { Text(risk.rawValue).font(.headline).padding(.top, 8); ForEach(items) { artifactRow($0) } }
            }
            if artifacts.isEmpty { empty("분석 결과 없음", subtitle: "빠른 분석 또는 전체 분석을 실행하세요.") }
        }
    }
    private func artifactRow(_ artifact: Artifact) -> some View {
        HStack(spacing: 16) {
            Image(systemName: artifact.canTrash ? "externaldrive.badge.checkmark" : "lock.shield").font(.title2).foregroundStyle(artifact.canTrash ? .mint : .secondary).frame(width: 35)
            VStack(alignment: .leading, spacing: 5) {
                Text(artifact.owner + " · " + artifact.url.lastPathComponent).font(.headline)
                Text(artifact.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(artifact.url.path)
                Text(artifact.reason).font(.caption).foregroundStyle(.secondary)
                if !artifact.measurement.complete { Text("일부 파일 측정 불가").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(Format.bytes(artifact.measurement.allocated)).font(.headline.monospacedDigit())
                Text("논리 \(Format.bytes(artifact.measurement.logical))").font(.caption2).foregroundStyle(.secondary)
            }
            Button { model.reveal(artifact.url) } label: { Image(systemName: "folder") }.help("Finder에서 보기")
            if artifact.canTrash { Button("미리보기") { model.prepare(artifact) }.disabled(model.working || model.scanning) }
        }.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    private var tools: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("APFS / Time Machine 스냅샷") { model.diagnose(snapshots: true) }
                Button("Simulator 상태 조회") { model.diagnose(snapshots: false) }
                Button("Xcode 열기") { model.open(URL(fileURLWithPath: "/Applications/Xcode.app")) }
                Button("Android Studio 열기") { model.open(URL(fileURLWithPath: "/Applications/Android Studio.app")) }
            }.disabled(model.working)
            HStack {
                Button("설치 도구 / NDK 의존성 확인") { model.inspectToolchains() }
                Button("MobileAsset 버전별 측정") { model.inspectAssets() }
            }.disabled(model.working)
            ForEach(model.installations) { installation in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(installation.name + " · " + installation.version).font(.headline); Text(installation.identity).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Finder") { model.reveal(installation.url) }
                }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(model.assets) { asset in
                HStack { Text("iOS " + asset.version + " · " + asset.build); Spacer(); Text(Format.bytes(asset.measurement.allocated)); Label("진단 전용", systemImage: "lock") }.padding(12)
            }
            Text(model.diagnostics).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            inventory(title: "설치 데이터와 공유 캐시", artifacts: (model.report?.artifacts ?? []).filter { $0.projectID == nil && $0.risk != .protected })
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("분석 및 정리 기록").font(.title3.bold()); Spacer(); Button("마스킹된 JSON 보고서 내보내기") { model.export() }.disabled(model.report == nil) }
            CapacityHistoryView()
            ForEach(model.cleanupHistory) { record in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(record.status).font(.headline); Spacer(); Text(record.date.formatted()).font(.caption).foregroundStyle(.secondary) }
                    Text(record.path).font(.caption).textSelection(.enabled)
                    if let reason = record.failureReason { Text(reason).foregroundStyle(.orange) }
                    if let delta = record.observedDelta {
                        Text("가용 공간 관측 변화: \(Format.bytes(delta)) · 다른 앱의 쓰기도 포함될 수 있습니다.").foregroundStyle(.secondary)
                    } else { Text("가용 공간 변화: 측정되지 않음").foregroundStyle(.secondary) }
                    if let path = record.trashPath {
                        Button("이동한 항목을 Finder에서 보기") { model.reveal(URL(fileURLWithPath: path)) }
                        Text("휴지통에서 ‘되돌려 놓기’를 사용할 수 있습니다. 이미 이동·삭제한 항목은 찾을 수 없습니다.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding()
            }
            ForEach(model.history) { scan in
                HStack { Image(systemName: "clock").foregroundStyle(.mint); Text(scan.startedAt.formatted()); Spacer(); Text(scan.mode); Text("프로젝트 \(scan.projects.count) · \(scan.isPartial ? "부분" : "완료")") }.padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.history.isEmpty { empty("아직 기록이 없습니다", subtitle: "검사 결과는 이 Mac의 SQLite 데이터베이스에 저장됩니다.") }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("상단 메뉴바 위젯") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("표시 항목", selection: $model.menuBarDisplay) {
                        ForEach(MenuBarDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("60초마다 갱신합니다. 상세 창을 닫아도 메뉴바에 유지되며 Dock에는 표시하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    Toggle("로그인 시 자동 실행", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                    Text(model.loginStatus).font(.caption).foregroundStyle(.secondary)
                    Button("macOS 로그인 항목 설정") { model.openLoginSettings() }
                }.padding(12)
            }
            GroupBox("점검 설정") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("전체 분석 이후 프로젝트 변경 감시 (FSEvents)", isOn: $model.monitoring)
                    Text(model.monitoringStatus).font(.caption).foregroundStyle(.secondary)
                    Toggle("앱 실행 중 매일 알려진 캐시 자동 분석", isOn: $model.automatic)
                    Stepper("여유 공간 경고: \(model.warningGB) GiB", value: $model.warningGB, in: 1...500)
                    Text("자동 삭제 없음. 용량은 앱 실행 중 60초마다 갱신됩니다.").font(.caption).foregroundStyle(.secondary)
                    Text("제외할 절대 경로 (한 줄에 하나)")
                    TextEditor(text: $model.exclusions).font(.system(.caption, design: .monospaced)).frame(height: 80)
                    Button("설정 저장") { model.persistSettings() }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("볼륨과 권한") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("기본 범위: \(VolumeInventory.dataRoot.path)")
                    ForEach(model.volumes.filter { $0.local && $0.url.path.hasPrefix("/Volumes/") }) { volume in
                        Toggle("추가 검사: \(volume.name)", isOn: Binding(get: { model.selectedExternal.contains(volume.id) }, set: { enabled in if enabled { model.selectedExternal.insert(volume.id) } else { model.selectedExternal.remove(volume.id) } }))
                    }
                    Button("전체 디스크 접근 권한 설정 열기") { model.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
                    Button("macOS 저장 공간 관리 열기") { model.open(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!) }
                    Text("FDA를 허용해도 SIP 보호 영역은 읽을 수 없을 수 있습니다. 네트워크 볼륨은 기본 검사에 포함되지 않습니다.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            DisclosureGroup("제외·접근 불가·미검사 영역 (\(model.report?.issues.count ?? 0))") {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array((model.report?.issues ?? []).enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading) { Text(issue.path).textSelection(.enabled); Text(issue.reason).foregroundStyle(.secondary) }.font(.caption)
                    }
                }.padding(.top, 12)
            }
        }
    }
    private func empty(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 12) { Image(systemName: "internaldrive").font(.largeTitle).foregroundStyle(.secondary); Text(title).font(.headline); Text(subtitle).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(35)
    }
}
