import SwiftUI
import StorageCore

struct DeveloperManagerView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("설치 버전과 기기를 개별 관리합니다").font(.title3.bold())
                Spacer()
                Button("목록 · 용량 새로고침") { model.refreshDeveloperInventory() }.disabled(model.working || model.scanning)
            }
            Text("이 화면은 자동으로 분석하지 않습니다. 새로고침할 때 설치 목록과 용량을 읽습니다. SDK와 기기 제거는 휴지통을 거치지 않으며 승인 후 공식 도구로 실행합니다.").foregroundStyle(.secondary)
            HStack {
                Button("Android Studio 열기") { model.open(URL(fileURLWithPath: "/Applications/Android Studio.app")) }
                Button("Xcode 열기") { model.open(URL(fileURLWithPath: "/Applications/Xcode.app")) }
                Button("Simulator 열기") { model.open(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")) }
            }
            ForEach(Array(model.developerInventory.issues.enumerated()), id: \.offset) { _, issue in Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if !model.developerLoaded { Text("새로고침하여 설치된 SDK와 시뮬레이터를 확인하세요.").padding(24) }
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
                    Text(package.bytes.map(Format.bytes) ?? "측정 불가").monospacedDigit()
                    Button("Finder") { model.reveal(package.location) }
                    if package.removable { Button("제거…") { model.prepareSDK(package) }.disabled(model.working || model.scanning) }
                    else { Text("SDK Manager 관리").font(.caption).foregroundStyle(.secondary) }
                }.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Simulator 기기").font(.title3.bold())
            ForEach(model.developerInventory.devices.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) }) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name).font(.headline)
                        Text(device.runtime).font(.caption)
                        Text("\(device.state) · \(device.available ? "사용 가능" : "런타임 사용 불가") · \(device.udid)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(device.bytes.map(Format.bytes) ?? "측정 불가").monospacedDigit()
                    Button(device.canDelete ? "기기 삭제…" : "종료 후 삭제 가능") { model.prepareDevice(device) }.disabled(!device.canDelete || model.working || model.scanning)
                }.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Simulator 런타임").font(.title3.bold())
            Text("런타임은 여러 기기가 공유합니다. Xcode > Settings > Components (또는 Platforms)에서 설치·제거하세요. 기기 삭제만으로 런타임 용량은 회수되지 않습니다.").font(.callout).foregroundStyle(.secondary)
            ForEach(model.developerInventory.runtimes) { runtime in
                HStack { Text(runtime.name + " · " + runtime.version); Spacer(); Text(runtime.available ? "사용 가능" : "사용 불가").foregroundStyle(.secondary) }.padding(10)
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
    }
}
