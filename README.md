# Mac Storage Doctor

macOS 14+용 Swift 6 / SwiftUI 메뉴바 저장 공간 분석 앱. 제공된 v1.2 설계를 기반으로 만든 **0.2 개발 버전**입니다. 설계 전체가 구현된 v1.2 출시본은 아닙니다.

## 빌드와 실행

Xcode 또는 Swift 6 도구체인이 필요합니다. 외부 패키지 다운로드 없이 macOS의 SQLite를 사용합니다.

```sh
./scripts/build-app.sh
open "dist/Mac Storage Doctor.app"
```

Xcode에서 `Package.swift`를 열어 `MacStorageDoctor` 실행 대상을 선택할 수도 있습니다. 번들은 로컬 개발용 ad-hoc 서명이며 배포용 Developer ID 서명·공증은 별도입니다.

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox --cache-path .build/cache
```

## 현재 제공하는 기능

- 실제 볼륨 가용 공간 표시와 60초 갱신, 메뉴바 팝오버, 8개 상세 화면
- 내부 Data 볼륨 전체에서 취소 가능한 프로젝트 탐색, 숨김 폴더 탐색, 외장 볼륨 선택
- RN/Expo, Flutter, Android, Xcode, Swift Package, Node 탐지와 네이티브 하위 프로젝트 묶기
- 알려진 캐시·앱 데이터·프로젝트 생성물 용량 측정, 프로젝트 Keep Warm
- 경로 제외, 생성물 내부 탐색 생략, 접근 오류와 볼륨 경계 기록
- 링크를 따라가지 않는 파일 측정, 측정 대상 내부 하드링크 중복 제외, 논리/할당 용량 분리
- 폴더별 탐색과 크기 막대, Finder 연결
- 앱 번들 ID 기반 IDE 구분, SDK/NDK/버전 관리자 설치 목록, 직접 지정된 NDK 요구 버전 진단
- APFS/Time Machine 스냅샷, simctl 읽기 전용 조회, MobileAsset 버전·빌드별 측정
- 검증된 Xcode DerivedData의 미리보기 → 개별 승인 → 휴지통 이동 → 전후 가용 공간 기록
- SQLite 검사·정리 이력, 사용자 홈을 마스킹한 JSON 보고서
- FSEvents 기반 프로젝트 증분 재검사, 변경 이벤트 병합과 이벤트 유실 시 복구 안내
- 빠른 분석과 별도로 유지되는 SQLite 프로젝트 인덱스
- 앱 실행 중 일일 캐시 분석 선택, 여유 공간 경고 기준 설정

첫 실행에서 전체 디스크 검사를 자동으로 시작하지 않습니다. `전체 분석`을 누르면 기본 Data 볼륨에서 탐색합니다. `빠른 분석`은 알려진 공용 캐시만 측정하며 프로젝트 탐색을 수행하지 않습니다. 두 결과는 별도 검사 이력으로 저장되며 빠른 분석 뒤에도 기존 프로젝트 목록은 유지됩니다. 시스템 데이터와 사용자 앱 데이터 측정은 디스크 상황에 따라 오래 걸릴 수 있습니다.

## 변경 감시

설정의 `전체 분석 이후 프로젝트 변경 감시`가 켜져 있으면 전체 분석 **직전에** FSEvents 감시를 시작합니다. 분석 중 발생한 관련 이벤트는 대기열에 보관하고, 이후 변경된 하위 트리만 재검사합니다. 프로젝트의 생성·삭제·이동과 식별 파일 변경을 처리하며 생성물 내부와 제외 경로는 무시합니다.

이벤트 유실·대량 변경·볼륨 분리·검사 취소 시에는 갱신을 중단하고 전체 분석 필요 배너를 표시합니다. 앱을 다시 실행하면 저장된 인덱스를 보여주되 실행 공백을 완전 검사로 간주하지 않습니다. 전체 분석으로 기준점을 새로 만들면 감시가 재개됩니다. 재시작 간 이벤트 커서 재생은 후속 작업입니다. 설정을 저장한 뒤에도 기준점 갱신을 위해 전체 분석이 필요합니다.

증분 검사 이력에는 해당 하위 트리 결과를 저장하고, `current-index`에는 병합 결과를 저장합니다. 빠른 분석 화면에 유지되는 프로젝트와 일부 캐시 수치는 이전 측정 시점의 결과일 수 있습니다.

실시간 이벤트 통합 테스트는 macOS FSEvents 서비스 접근이 필요하며, 제한된 샌드박스에서는 실행할 수 없습니다.

## 정리 정책

직접 정리는 `~/Library/Developer/Xcode/DerivedData` 바로 아래에서 `info.plist`의 WorkspacePath가 확인된 디렉터리에 한정됩니다. 나머지는 진단 또는 공식 도구 안내입니다. 소스·SDK·앱 DB·시스템 관리 자산을 삭제하는 명령은 없습니다.

정리 전에 canonical path, 모든 상위 경로의 링크 여부, device/inode/mtime, 하위 항목 지문, Keep Warm, 실행 중인 빌드 프로세스를 확인합니다. 링크·보호 파일·다른 볼륨이 포함되면 거절합니다. 승인은 5분 내 한 번만 사용할 수 있습니다. 휴지통은 비우지 않으며 이동 결과를 **미회수**로 표시합니다. 전후 가용 공간 차이는 다른 앱의 쓰기를 포함한 관측값입니다.

파일시스템은 검사 직후에도 변할 수 있습니다. 현재 Foundation 기반 휴지통 작업은 검증과 이동 사이의 경쟁을 완전히 없애는 보안 경계를 제공하지 않습니다. 프로덕션 출시 전 descriptor 기반 경쟁 조건 강화 및 실제 동시 쓰기 QA가 필요합니다. 현재 앱은 관리자 권한을 요구하지 않습니다.

## 데이터와 권한

SQLite: `~/Library/Application Support/MacStorageDoctor/history.sqlite`

설정: `dev.macstoragedoctor.app` UserDefaults. 로컬 이력은 경로를 그대로 저장합니다. 내보내기는 `/Users/<사용자>`만 마스킹하므로 프로젝트명과 사용자 정의 볼륨명은 공유 전에 확인하세요.

Full Disk Access는 설정 화면에서 사용자가 허용할 수 있습니다. SIP 보호 영역·네트워크·기본 제외 클라우드 경로는 완전 검사로 주장하지 않습니다. 외장 볼륨 선택은 현재 세션에 적용됩니다.

## 남은 출시 작업

[구현 상태 및 수용 기준](docs/IMPLEMENTATION_STATUS.md)을 확인하세요. Spotlight, 재시작 시 FSEvents 이력 재생, 공식 패키지 캐시 실행, SDK 삭제·복원, Simulator 삭제, 앱별 세부 캐시 정책, 로그인 항목·시스템 알림, 히스토리 집계와 배포 공증은 미구현입니다.

## 구조

- `Sources/StorageCore`: 분류, 크롤러, 측정, 정책·정리, 도구 진단, SQLite
- `Sources/MacStorageDoctor`: SwiftUI 화면과 상태 관리
- `Tests/StorageCoreTests`: 격리된 임시 폴더에서 발견·측정·보호 정책·DB 검증
- `scripts/build-app.sh`: release 실행 파일과 `.app` 생성

참고 API: [Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [FileManager trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)).
