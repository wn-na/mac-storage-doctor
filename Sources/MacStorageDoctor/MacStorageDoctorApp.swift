import SwiftUI
import AppKit
import StorageCore

@main
struct MacStorageDoctorApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Mac Storage Doctor", id: "main") {
            MainView().environmentObject(model).frame(minWidth: 1040, minHeight: 700)
        }.defaultSize(width: 1250, height: 820)
        MenuBarExtra {
            MenuOverview().environmentObject(model)
        } label: {
            Label(model.volume.map { Format.bytes($0.available) } ?? "Storage", systemImage: "internaldrive")
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
            Text("프로젝트 \(model.report?.projects.count ?? 0)개 · \(model.report?.isPartial == false ? "선택 범위 검사 완료" : "부분 검사 / 미검사")").foregroundStyle(.secondary)
            HStack {
                Button("빠른 분석") { model.scan(quick: true) }.disabled(model.scanning || model.working)
                Button("상세 보기") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            }
            if model.scanning { ProgressView().controlSize(.small) }
            Divider()
            Button("종료") { model.cancel(); NSApp.terminate(nil) }
        }.padding(22).frame(width: 340)
    }
}
