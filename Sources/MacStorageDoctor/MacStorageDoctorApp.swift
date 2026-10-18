import SwiftUI
import AppKit
import StorageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct MacStorageDoctorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Mac Storage Doctor", id: "main") {
            MainView().environmentObject(model).frame(minWidth: 1040, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.shutdown() }
        }.defaultSize(width: 1250, height: 820)
        MenuBarExtra {
            MenuOverview().environmentObject(model)
        } label: {
            Label(model.menuBarLabel, systemImage: model.lowSpace ? "exclamationmark.triangle.fill" : "internaldrive")
                .help("Mac Storage Doctor · " + model.menuBarDisplay.title + " · 60초마다 갱신")
        }.menuBarExtraStyle(.window)
    }
}
struct MenuOverview: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Mac Storage Doctor", systemImage: "cross.case.fill").font(.headline)
            Text(model.volume.map { Format.bytes($0.available) + " 사용 가능" } ?? "용량 확인 불가").font(.title2.bold())
            if let volume = model.volume { ProgressView(value: Double(volume.used), total: Double(max(1, volume.total))) }
            if model.lowSpace { Label("여유 공간 부족", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Picker("메뉴바 표시", selection: $model.menuBarDisplay) {
                ForEach(MenuBarDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Text("프로젝트 \(model.report?.projects.count ?? 0)개 · \(model.report?.isPartial == false ? "선택 범위 검사 완료" : "부분 검사 / 미검사")").foregroundStyle(.secondary)
            HStack {
                Button("빠른 분석") { model.scan(quick: true) }.disabled(model.scanning || model.working)
                Button("상세 보기") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            }
            if model.scanning { ProgressView().controlSize(.small) }
            Divider()
            HStack {
                Button("새로고침") { model.refreshCapacity() }
                Spacer()
                Button("종료") { model.shutdown(); NSApp.terminate(nil) }
            }
            Text("상세 창을 닫아도 메뉴바에서 계속 실행됩니다.").font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 340)
    }
}
