import SwiftUI
import StorageCore

struct DeveloperManagerView: View {
    @Environment(AppModel.self) private var model
    @State private var section = 0
    private var selectedDevices: [SimulatorDevice] {
        model.developerInventory.devices.filter { model.selectedDevices.contains($0.id) }
    }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("설치 버전과 기기를 개별 관리합니다").font(.title3.bold())
                Spacer()
                Button("목록 새로고침") { model.refreshDeveloperInventory() }.disabled(model.working || model.scanning)
            }
            Text("처음 열 때 설치 목록만 한 번 조회합니다. 폴더 용량은 ‘용량 측정’을 누를 때만 분석합니다. SDK와 기기 제거는 승인 후 공식 도구로 실행합니다.").foregroundStyle(.secondary)
            HStack {
                Picker("관리 대상", selection: $section) {
                    Text("SDK (\(model.developerInventory.packages.count))").tag(0)
                    Text("Simulator 기기 (\(model.developerInventory.devices.count))").tag(1)
                    Text("런타임 (\(model.developerInventory.runtimes.count))").tag(2)
                }.pickerStyle(.segmented)
                Button("용량 측정") { model.refreshDeveloperInventory(measureSizes: true) }.disabled(model.working || model.scanning)
            }
            HStack {
                Button("Android Studio 열기") { model.open(URL(fileURLWithPath: "/Applications/Android Studio.app")) }
                Button("Xcode 열기") { model.open(URL(fileURLWithPath: "/Applications/Xcode.app")) }
                Button("Simulator 열기") { model.open(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")) }
            }
            ForEach(Array(model.developerInventory.issues.enumerated()), id: \.offset) { _, issue in Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if !model.developerLoaded { Text(model.working ? "설치 목록을 불러오는 중…" : "진행 중인 작업이 끝나면 목록을 불러옵니다.").padding(24) }
            if section == 0 {
            Text("Android SDK 패키지").font(.title3.bold())
            Text("SDK Tools에서 Command-line Tools를 설치해야 합니다. 알려진 프로젝트의 버전 참조 또는 Keep Warm이 있으면 제거를 차단합니다. 나머지 의존성은 직접 확인해야 합니다.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.developerInventory.packages.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) }) { package in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(package.name + " · " + package.version).font(.headline)
                        Text(package.packageID).font(.caption).textSelection(.enabled)
                        Text(package.root.path).font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("재설치 방법") { Text(package.restoreCommand + "\n라이선스 요청 시 Android Studio SDK Manager에서 설치하세요.").font(.caption).textSelection(.enabled) }
                    }
                    Spacer()
                    Text(package.bytes.map(Format.bytes) ?? (model.developerSizesRequested ? "측정 불가" : "용량 미측정")).monospacedDigit()
                    Button("Finder") { model.reveal(package.location) }
                    if package.removable { Button("제거…") { model.prepareSDK(package) }.disabled(model.working || model.scanning) }
                    else { Text("SDK Manager 관리").font(.caption).foregroundStyle(.secondary) }
                }.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            if model.developerLoaded && model.developerInventory.packages.isEmpty {
                Text(model.developerInventory.issues.contains { $0.hasPrefix("Android SDK") } ? "SDK 목록을 조회하지 못했습니다. 위 오류를 확인하세요." : "알려진 SDK 경로에 설치된 패키지가 없습니다.").foregroundStyle(.secondary)
            }
            }
            if section == 1 {
            Text("Simulator 클린").font(.title3.bold())
            Text("데이터 초기화는 기기를 남기고 앱·사진·설정을 모두 지웁니다. 기기 삭제는 등록까지 제거합니다. 두 작업 모두 복구할 수 없으며 공용 런타임은 유지됩니다.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("사용 불가 기기 선택") {
                    model.selectedDevices = Set(model.developerInventory.devices.filter { !$0.available && $0.canDelete }.map(\.id))
                }
                Button("종료된 기기 선택") {
                    model.selectedDevices = Set(model.developerInventory.devices.filter(\.canDelete).map(\.id))
                }
                Button("선택 해제") { model.selectedDevices.removeAll() }
            }.disabled(model.working || model.scanning)
            HStack {
                Text("선택 \(selectedDevices.count)개 · 측정된 기기 용량 \(Format.bytes(selectedDevices.compactMap(\.bytes).reduce(0, +)))").font(.caption)
                Spacer()
                Button("데이터 초기화…") { model.prepareSimulatorCleanup(.erase) }
                    .disabled(selectedDevices.isEmpty || selectedDevices.contains { !$0.canDelete || !$0.available } || model.working || model.scanning)
                Button("선택 기기 삭제…") { model.prepareSimulatorCleanup(.delete) }
                    .disabled(selectedDevices.isEmpty || selectedDevices.contains { !$0.canDelete } || model.working || model.scanning)
            }
            Text("용량은 마지막 측정값이며 실제 회수량과 다릅니다. 미측정 \(selectedDevices.filter { $0.bytes == nil }.count)개. 실행 중인 기기는 Simulator에서 종료한 뒤 목록을 새로고침하세요.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.developerInventory.devices.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) }) { device in
                HStack {
                    Toggle("선택", isOn: Binding(get: { model.selectedDevices.contains(device.id) }, set: { selected in
                        if selected { model.selectedDevices.insert(device.id) } else { model.selectedDevices.remove(device.id) }
                    })).toggleStyle(.checkbox).labelsHidden().accessibilityLabel(device.name + " 선택")
                        .disabled(!device.canDelete || model.working || model.scanning)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name).font(.headline)
                        Text(device.runtime).font(.caption)
                        Text("\(device.state) · \(device.available ? "사용 가능" : "런타임 사용 불가") · \(device.udid)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(device.bytes.map(Format.bytes) ?? (model.developerSizesRequested ? "측정 불가" : "용량 미측정")).monospacedDigit()
                    Button(device.canDelete ? "기기 삭제…" : "종료 후 삭제 가능") { model.prepareDevice(device) }.disabled(!device.canDelete || model.working || model.scanning)
                }.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            if model.developerLoaded && model.developerInventory.devices.isEmpty {
                Text(model.developerInventory.issues.contains { $0.hasPrefix("Simulator:") } ? "Simulator 목록을 조회하지 못했습니다. 위 오류를 확인하세요." : "등록된 Simulator 기기가 없습니다.").foregroundStyle(.secondary)
            }
            }
            if section == 2 {
            Text("Simulator 런타임").font(.title3.bold())
            Text("런타임은 여러 기기가 공유합니다. Xcode > Settings > Components (또는 Platforms)에서 설치·제거하세요. 기기 삭제만으로 런타임 용량은 회수되지 않습니다.").font(.callout).foregroundStyle(.secondary)
            ForEach(model.developerInventory.runtimes) { runtime in
                HStack { Text(runtime.name + " · " + runtime.version); Spacer(); Text(runtime.available ? "사용 가능" : "사용 불가").foregroundStyle(.secondary) }.padding(10)
            }
            if model.developerLoaded && model.developerInventory.runtimes.isEmpty {
                Text(model.developerInventory.issues.contains { $0.hasPrefix("Simulator:") } ? "런타임 목록을 조회하지 못했습니다. 위 오류를 확인하세요." : "등록된 Simulator 런타임이 없습니다.").foregroundStyle(.secondary)
            }
            }
            DisclosureGroup("추가 진단") {
                HStack {
                    Button("APFS / Time Machine") { model.diagnose(snapshots: true) }
                    Button("도구 / NDK 의존성") { model.inspectToolchains() }
                    Button("MobileAsset 측정") { model.inspectAssets() }
                }.disabled(model.working || model.scanning)
                Text(model.diagnostics).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding()
            }
        }
        .task(id: model.working || model.scanning || model.hasApproval) {
            if !model.developerLoaded { model.refreshDeveloperInventory() }
        }
    }
}
