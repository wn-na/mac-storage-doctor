import SwiftUI

struct TutorialView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    private let titles = ["먼저, Mac의 공간을 확인하세요", "유형과 용량 상위 10개를 비교하세요", "선택 정리 또는 빠른 정리", "SDK와 시뮬레이터는 따로 관리", "필요할 때 분석하세요"]
    private let descriptions = [
        "메뉴바에서 여유 공간을 상시 확인할 수 있습니다. 60초마다 용량만 읽으며 폴더를 분석하지 않습니다. ‘캐시 분석’은 알려진 공용 항목을, ‘전체 분석’은 프로젝트 생성물까지 찾습니다.",
        "저장 공간 · 정리 화면에서 빌드 생성물, 설치 의존성, 공유 캐시, SDK, 사용자 데이터를 구분합니다. 기본 목록은 측정된 항목 중 큰 순서 10개입니다. 필터와 검색으로 대상을 좁힐 수 있습니다.",
        "체크박스로 고른 뒤 ‘선택 정리’를 누르세요. ‘빠른 정리’는 기존 분석에서 재생성 가능한 빌드 생성물만 골라 확인합니다. 두 방식 모두 한 번 승인하면 휴지통으로 이동합니다. 휴지통을 비워야 실제 공간이 회수됩니다. Keep Warm 프로젝트와 안전 검사에 실패한 항목은 제외됩니다.",
        "SDK · 시뮬레이터에서 목록을 새로고침하고 버전·용량·상태를 확인하세요. SDK는 sdkmanager, 종료된 Simulator 기기는 simctl로 개별 제거합니다. 기기의 앱·테스트 데이터는 복구되지 않습니다. 런타임 설치·제거는 Xcode 설정에서 관리합니다.",
        "기본은 수동 분석입니다. 설정에서 하루 한 번 캐시 분석과 15·30·60분 간격 변경 감시를 선택할 수 있습니다. 프로젝트의 Keep Warm은 빌드 캐시를 보호합니다. 실패한 작업의 이유는 기록 화면에서 확인하며 이 튜토리얼은 설정에서 다시 볼 수 있습니다."
    ]
    private let icons = ["menubar.rectangle", "list.number", "checklist", "hammer", "clock"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Label("Mac Storage Doctor 시작하기", systemImage: "cross.case.fill").font(.headline); Spacer(); Text("\(step + 1) / \(titles.count)").foregroundStyle(.secondary) }
            Image(systemName: icons[step]).font(.system(size: 52)).foregroundStyle(.mint)
            Text(titles[step]).font(.title.bold())
            Text(descriptions[step]).font(.body).lineSpacing(6).frame(minHeight: 130, alignment: .top)
            HStack {
                Button("나중에 보기") { model.finishTutorial() }
                Spacer()
                if step > 0 { Button("이전") { step -= 1 } }
                Button(step == titles.count - 1 ? "시작하기" : "다음") {
                    if step == titles.count - 1 { model.finishTutorial() } else { step += 1 }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(32).frame(width: 630)
    }
}
