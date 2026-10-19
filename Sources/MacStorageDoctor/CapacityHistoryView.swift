import SwiftUI
import Charts
import StorageCore

struct CapacityHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDate: Date?
    private var selected: CapacityPoint? {
        guard let selectedDate else { return nil }
        return model.capacityPoints.min { abs($0.bucket.timeIntervalSince(selectedDate)) < abs($1.bucket.timeIntervalSince(selectedDate)) }
    }
    var body: some View {
        @Bindable var model = model
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("사용 가능한 공간 변화", systemImage: "chart.xyaxis.line").font(.headline)
                    Spacer()
                    Picker("기간", selection: $model.capacityRange) {
                        ForEach(CapacityRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 300)
                }
                if let error = model.capacityError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if model.capacityPoints.isEmpty {
                    Text("선택한 기간에 관측 기록이 없습니다.").foregroundStyle(.secondary).frame(height: 120)
                } else {
                    Chart(model.capacityPoints) { point in
                        RuleMark(x: .value("시각", point.bucket),
                                 yStart: .value("최소 GiB", Double(point.minimumAvailable) / 1_073_741_824),
                                 yEnd: .value("최대 GiB", Double(point.maximumAvailable) / 1_073_741_824))
                            .foregroundStyle(.mint.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 5))
                        PointMark(x: .value("시각", point.bucket), y: .value("평균 GiB", point.averageAvailable / 1_073_741_824))
                            .foregroundStyle(.mint).symbolSize(28)
                            .accessibilityLabel(point.firstDate.formatted())
                            .accessibilityValue("평균 여유 공간 \(Format.bytes(Int64(point.averageAvailable))) · \(point.count)회 관측")
                    }
                    .chartYAxisLabel("GiB")
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 180)
                    if let point = selected ?? model.capacityPoints.last {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(point.firstDate.formatted()) – \(point.lastDate.formatted()) · \(point.count)회 관측")
                            Text("평균 \(Format.bytes(Int64(point.averageAvailable))) · 최소 \(Format.bytes(point.minimumAvailable)) · 최대 \(Format.bytes(point.maximumAvailable))")
                        }.font(.caption).monospacedDigit()
                    }
                    if let first = model.capacityPoints.first, let last = model.capacityPoints.last {
                        Text("기간 내 첫·마지막 관측 차이: \(Format.bytes(last.lastAvailable - first.firstAvailable))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("앱 실행 중 1분마다 기록합니다. 점은 관측 평균, 세로 막대는 최소–최대입니다. 미관측 시간은 보간하지 않습니다. 30일 상세, 12개월 주별, 이후 월별 보관합니다. 집계는 UTC 기준이며 월 경계의 주는 나눕니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("다른 앱의 쓰기와 APFS 공간 공유도 반영되므로 정리로 회수한 용량과 같지 않을 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.observeCapacityHistory(true) }
        .onDisappear { model.observeCapacityHistory(false) }
        .onChange(of: model.capacityRange) { selectedDate = nil }
    }
}
