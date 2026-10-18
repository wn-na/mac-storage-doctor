import SwiftUI
import StorageCore

struct BatchCleanupSheet: View {
    @EnvironmentObject var model: AppModel
    let batch: BatchCleanupPreview
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("선택 항목 정리", systemImage: "trash").font(.title2.bold())
            Text("검증 통과 \(batch.items.count)개 · \(Format.bytes(batch.items.reduce(0) { $0 + $1.artifact.measurement.allocated }))")
            Text("휴지통으로 이동합니다. 다시 빌드하거나 의존성을 재설치해야 합니다. 휴지통을 비우기 전에는 복원할 수 있으며 여유 공간은 바로 늘지 않습니다.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(batch.items) { item in
                        VStack(alignment: .leading) { Text(item.artifact.owner).bold(); Text(item.artifact.url.path).font(.caption); Text(Format.bytes(item.artifact.measurement.allocated)).font(.caption) }
                    }
                    if !batch.skipped.isEmpty {
                        Text("안전 검사에서 제외된 항목").font(.headline).foregroundStyle(.orange)
                        ForEach(Array(batch.skipped.enumerated()), id: \.offset) { _, reason in Text(reason).font(.caption).textSelection(.enabled) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 320)
            Text("승인은 5분 동안 유효하며 실행 직전 다시 검사합니다. 보호 설정·파일 변경·실행 중인 빌드가 있으면 해당 항목을 건너뜁니다.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("취소") { model.batchPreview = nil }; Button("\(batch.items.count)개 휴지통으로 이동") { model.cleanBatch(batch) }.buttonStyle(.borderedProminent).disabled(batch.items.isEmpty) }
        }.padding(28).frame(width: 640)
    }
}
struct ManagedRemovalSheet: View {
    @EnvironmentObject var model: AppModel
    let preview: ManagedRemovalPreview
    @State private var acknowledged = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("공식 도구로 제거", systemImage: "exclamationmark.triangle").font(.title2.bold()).foregroundStyle(.orange)
            Text(preview.title).font(.headline)
            Text(preview.impact).textSelection(.enabled)
            Text(preview.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Toggle("영구 삭제와 의존성 영향을 확인했습니다", isOn: $acknowledged)
            HStack { Spacer(); Button("취소") { model.managedPreview = nil }; Button("선택 항목 영구 제거", role: .destructive) { model.removeManaged(preview) }.disabled(!acknowledged) }
        }.padding(28).frame(width: 640)
    }
}
