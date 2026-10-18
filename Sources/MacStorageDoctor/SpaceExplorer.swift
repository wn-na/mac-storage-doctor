import SwiftUI
import AppKit
import StorageCore

private struct SpaceEntry: Identifiable, Sendable {
    var id: String { url.path }
    var url: URL
    var measurement: StorageCore.Measurement
    var directory: Bool
}
struct SpaceExplorer: View {
    @State private var root = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [SpaceEntry] = []
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { root.deleteLastPathComponent(); measure() } label: { Image(systemName: "arrow.up") }.disabled(busy)
                Text(root.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("폴더 선택") { choose() }.disabled(busy)
                Button("측정") { measure() }.disabled(busy)
                if busy { Button("취소") { task?.cancel() }; ProgressView().controlSize(.small) }
            }
            Text("직접 하위 항목의 크기를 측정합니다. 다른 파일시스템과 심볼릭 링크는 따라가지 않습니다. APFS 공유 블록으로 합계는 실제 사용량과 다를 수 있습니다.").foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange) }
            let total = max(1, entries.reduce(Int64(0)) { $0 + $1.measurement.allocated })
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(entries.prefix(12).enumerated()), id: \.element.id) { index, item in
                        let width = max(0, geometry.size.width * Double(item.measurement.allocated) / Double(total) - 2)
                        Rectangle().fill(Color(hue: 0.38 + Double(index) * 0.035, saturation: 0.5, brightness: 0.75)).frame(width: width)
                            .help("\(item.url.lastPathComponent): \(Format.bytes(item.measurement.allocated))")
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 8))
            }.frame(height: 45)
            ForEach(entries) { entry in
                HStack {
                    Image(systemName: entry.directory ? "folder.fill" : "doc").foregroundStyle(.mint)
                    Button(entry.url.lastPathComponent) { if entry.directory { root = entry.url; measure() } }.buttonStyle(.plain).disabled(busy)
                    if !entry.measurement.complete { Text("부분 측정").font(.caption).foregroundStyle(.orange) }
                    Spacer()
                    Text(Format.bytes(entry.measurement.allocated)).monospacedDigit()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } label: { Image(systemName: "arrow.up.forward.square") }
                }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }.onDisappear { task?.cancel() }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { root = url; measure() }
    }
    private func measure() {
        guard !busy else { return }; busy = true; error = nil; entries = []
        let selectedRoot = root
        task = Task {
            let worker = Task.detached(priority: .utility) { () -> ([SpaceEntry], String?) in
                do {
                    let boundary = try FileSystem.metadata(selectedRoot).st_dev
                    var result: [SpaceEntry] = []
                    for child in try FileSystem.children(selectedRoot) {
                        try Task.checkCancellation()
                        let s = try FileSystem.metadata(child)
                        guard !FileSystem.isLink(s), s.st_dev == boundary else { continue }
                        result.append(SpaceEntry(url: child, measurement: FileSystem.measure(child), directory: FileSystem.isDirectory(s)))
                    }
                    return (result.sorted { $0.measurement.allocated > $1.measurement.allocated }, nil)
                } catch { return ([], error.localizedDescription) }
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            entries = result.0; error = result.1; busy = false
        }
    }
}
