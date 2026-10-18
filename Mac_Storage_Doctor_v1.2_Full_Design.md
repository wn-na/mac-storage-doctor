# Mac Storage Doctor v1.2 — Universal Storage & System Cache Doctor

**문서 유형:** 통합 PRD + 기능 명세 + 시스템 아키텍처 + 안전 정리 정책 + 테스트/수용 기준  
**플랫폼:** macOS 14+ · Apple Silicon 우선, Intel 호환 검토  
**구현:** Swift 6 / SwiftUI / AppKit / Foundation / FSEvents / SQLite  
**제품 형태:** 메뉴바 유틸리티 + 상세 분석 창  
**핵심 원칙:** 자동 발견(Discover) → 시스템/개발 캐시 분류(Classify) → 분석(Analyze) → 사전 검증(Validate) → 사용자 승인(Clean) → 실제 회수량 측정(Verify)

## 1. 제품 목표와 범위

Mac의 **접근 가능한 모든 로컬 파일시스템 영역**에서 프로젝트와 개발 도구를 자동 발견한다. 사용자가 `~/Git`, `~/Projects` 등의 경로를 입력하는 것은 필수 과정이 아니다. React Native뿐 아니라 Android Native, iOS Native, Flutter, 다중 플랫폼 앱, 플러그인 및 모노레포를 하나의 모델로 지원한다.

지원 대상은 프로젝트 폴더뿐 아니라 다음의 **공용 개발 데이터**도 포함한다.

- Xcode DerivedData, Archives, DeviceSupport, Simulator 및 MobileAsset 자산
- Android SDK / NDK / Build Tools / AVD / Gradle / Kotlin / CMake
- Flutter SDK 및 Flutter/Dart Pub 캐시, FVM·Puro 등의 다중 버전 설치
- npm / Yarn / pnpm / CocoaPods / Swift Package Manager / Carthage
- VS Code / Cursor / Android Studio / Xcode / JetBrains / Unity / Homebrew / Docker(분석 중심)

**범위 한계:** 시스템 캐시도 지원하지만 macOS가 보호·관리하는 영역은 탐지/설명/공식 관리 화면 안내까지만 제공한다. Full Disk Access가 있어도 SIP 및 접근 제어로 읽을 수 없는 디렉터리가 있을 수 있고, 네트워크 디스크·iCloud 미다운로드 파일·오프라인 외장 SSD의 모든 파일을 자동 발견할 수 있는 것은 아니다. 이때 '완료' 대신 **부분 검사, 접근 거부, 연결되지 않은 볼륨**을 명시한다.

## 2. 메뉴바 UX

**메뉴바:** `◉ 111 GiB` 형태의 여유 공간 표시. 사용량/여유 공간 선택, 임계값 사용자 설정, 최근 검사 시각 노출.

```text
┌──────────────────────────────────────────────┐
│ Mac Storage Doctor                     ⚙    │
│                                              │
│ 111 GiB 사용 가능  ·  75% 사용 중             │
│ ████████████████░░░░░░                       │
│                                              │
│ 자동 발견 프로젝트  32개                     │
│ Android 12 · iOS 8 · Flutter 6 · RN 6        │
│ ※ 중복 플랫폼 프로젝트는 묶어서 계산          │
│                                              │
│ 안전한 캐시 정리 후보       6.4 GiB          │
│ 확인이 필요한 정리 후보    21.8 GiB          │
│ 보호된 시스템 자산        별도 진단          │
│                                              │
│ [빠른 분석] [스마트 정리] [모든 프로젝트]     │
│ 마지막 검사: 12분 전 · 범위: 96% 검사         │
└──────────────────────────────────────────────┘
```

표시 숫자는 예시이며 실제 결과는 재검사값을 사용한다. 메뉴바 클릭으로 경량 팝오버를 열고 상세 분석은 별도 창으로 제공한다.

### 상세 창 주요 탭

1. **Overview** — 볼륨 상태, 가용 공간, 증가 추세, 검사 누락 영역
2. **Projects** — 자동 발견 프로젝트, 플랫폼 태그, 프로젝트별 아티팩트 트리
3. **Toolchains** — 설치된 Xcode/Android/Flutter/SDK/IDE 및 버전
4. **Cleaner** — 안전/조건부/보호 항목별 분석과 선택적 정리
5. **Storage Explorer** — 대용량 폴더 트리·Treemap·Finder 열기
6. **History & Settings** — 검사 스냅샷, 스케줄, 권한, 제외 설정

## 3. 프로젝트 유형과 탐지 규칙

| 프로젝트 종류 | 강한 식별 신호 | 추가 신호 | 대표 분석 아티팩트 |
|---|---|---|---|
| **React Native** | `package.json`의 `react-native` 의존성 | `app.json`, `metro.config.js`, `android/`, `ios/` | `node_modules`, `android/**/build`, `ios/Pods`, Metro/Watchman 캐시 |
| **Expo** | `package.json`의 `expo` 의존성 | `app.config.*`, `.expo` | `.expo`, `node_modules`, prebuild 네이티브 아티팩트 |
| **Android Native** | `settings.gradle(.kts)`와 Gradle 모듈 선언 | `gradlew`, Android 플러그인, `AndroidManifest.xml` | `<module>/build`, `.gradle`, `.cxx`, `.externalNativeBuild` |
| **iOS Native** | `.xcodeproj/project.pbxproj` 또는 `Package.swift` + Apple 타깃 단서 | `.xcworkspace`, `Podfile`, `*.xcconfig` | DerivedData, `build`, `Pods`, SPM 체크아웃 및 빌드 캐시 |
| **Flutter** | `pubspec.yaml`의 Flutter SDK 의존성 | `lib/main.dart`, `.metadata`, `android/`, `ios/`, `macos/` | `build`, `.dart_tool`, `ios/Pods`, `.gradle`, Pub 캐시 |
| **Flutter Module/Plugin** | Flutter `pubspec.yaml`의 `module`/`plugin` | `.android`, `.ios`, 예제 앱 | 모듈 및 호스트 빌드 산출물 |
| **Multiplatform/Monorepo** | 여러 프로젝트 식별자 + 워크스페이스 구성 | pnpm/yarn workspaces, Melos, Gradle composite build | 서브프로젝트별 아티팩트, 공용 캐시 별도 |

### 판정 원칙

- **확장자가 아닌 파일 내용과 폴더 구조**를 함께 본다. 단순 `pubspec.yaml`은 Dart 프로젝트일 수도 있으므로 Flutter로 단정하지 않는다.
- `android/`와 `ios/`가 있다는 이유로 Flutter/RN을 Android·iOS 독립 프로젝트로 **중복 등록하지 않는다**. 하나의 프로젝트에 `platforms = {flutter, android, ios}` 등의 태그를 붙인다.
- 모노레포의 루트와 앱 패키지를 `Workspace → Projects → Modules → Artifacts` 계층으로 표시한다.
- 네이티브 앱이 Flutter 모듈을 포함하는 **Add-to-App**, 네이티브 모듈을 포함하는 RN 프로젝트 등 혼합 형태를 지원한다.
- `.git` 디렉터리뿐 아니라 Git worktree의 `.git` **파일**도 처리한다. Git 저장소라는 이유만으로 앱으로 분류하지 않는다.
- 탐지된 프로젝트에 **신뢰도(high/medium/unknown)** 및 발견 근거를 저장한다. 오탐을 수정하면 다음 검사에 반영한다.

## 4. 완전 자동 폴더 발견 설계

### 4.1 최초 실행: Discovery Pipeline

```text
Mounted Volume Inventory
  → Permission / Accessibility Check
  → Fast Discovery (Spotlight + 알려진 IDE 프로젝트 기록)
  → Full Accessible File-System Crawl
  → Project Signature Detection
  → Toolchain / Shared Cache Discovery
  → Workspace / Project / Module Grouping
  → Artifact Measurement
  → SQLite Index + Scan Coverage Report
```

**1. 볼륨 열거**

- `FileManager.mountedVolumeURLs` 및 볼륨 UUID로 로컬 APFS 볼륨을 식별한다.
- 시작 범위는 접근 가능한 **내장 로컬 데이터 볼륨 전체**다. `~/Git` 같은 고정 경로에 제한하지 않는다.
- 외장 SSD는 검색 가능 여부를 알리고 처음에 선택적으로 활성화한다. 네트워크 및 클라우드 경로는 기본적으로 대용량 전체 검사에서 제외한다.
- `/System/Volumes/Data`와 `/Users`의 동일 파일, `/Volumes` 마운트 경로 등을 **중복 탐색하지 않는다**. 볼륨 UUID·파일 ID로 식별한다.

**2. Fast Discovery**

- Spotlight의 `NSMetadataQuery`로 `package.json`, `pubspec.yaml`, `settings.gradle`, `settings.gradle.kts`, `Package.swift`, `.xcodeproj`, `.xcworkspace` 등 **후보 경로**를 찾는다.
- Xcode/Android Studio/VS Code/Cursor의 최근 프로젝트 목록은 보조 신호로만 활용한다. 개인정보와 접근 권한을 고려하고 임의의 IDE 데이터베이스를 변경하지 않는다.
- Spotlight가 반환하지 못한 파일은 다음 단계가 보완한다.

**3. Full Crawl**

- `FileManager` 열거 또는 저수준 파일 메타데이터 순회를 이용해 접근 가능한 볼륨 전체를 **취소 가능한 백그라운드 작업**으로 탐색한다.
- 숨김 폴더(`.projects`, `.workspace` 등)도 프로젝트 발견 대상이다.
- `node_modules`, `.git/objects`, `.gradle/caches`, DerivedData 등 **이미 용도를 식별한 거대 생성물 내부는 프로젝트 검색을 위해 끝까지 재귀 탐색하지 않는다**. 용량은 별도 측정한다.
- 심볼릭 링크는 기본적으로 재귀 추적하지 않는다. 별칭/링크의 원본은 별도 표기한다.
- 검사 중 파일이 이동·삭제될 수 있으므로 오류를 개별 파일 단위로 기록하고 전체 검사를 중단하지 않는다.
- 무제한 병렬화하지 않고 볼륨별 동시성 및 I/O 예산을 제한한다.

**4. Discovery Coverage**

- 발견한 프로젝트 수만 보여주지 않는다.
- `탐색 완료 / 미탐색 / 접근 거부 / 네트워크·외장 오프라인 / 제외 설정`의 범위를 표시한다.
- '모든 폴더를 찾았다'는 표현은 실제로 전체 범위의 검사가 완료된 경우에만 사용한다.

### 4.2 최초 이후: Incremental Discovery

- 파일 및 디렉터리 변경 탐지에는 Apple **FSEvents**를 사용한다.
- 새로운 `pubspec.yaml`, `settings.gradle`, `.xcodeproj`, `package.json` 생성 또는 삭제 이벤트가 들어오면 해당 하위 트리를 다시 검사한다.
- FSEvents는 디렉터리 단위 변경을 알려주는 **힌트**로 사용한다. 유실 이벤트·대량 변경 시 전체 또는 부분 재스캔으로 복구한다.
- 로그인 시 빠른 검사, 매일 Quick Scan, 사용자가 지정한 주기의 Full Scan을 실행한다.
- 배터리 사용 중·낮은 여유 공간·높은 디스크 부하에서는 Deep Scan을 연기할 수 있다.

## 5. 툴체인 및 SDK 설치 위치 자동 발견

| 도구 | 발견 전략 | 주의사항 |
|---|---|---|
| Xcode | `xcode-select`, `xcrun`, LaunchServices, Applications 내 Xcode 번들 | 여러 Xcode 버전별 Developer 경로 구분 |
| Android SDK | `ANDROID_HOME`, `ANDROID_SDK_ROOT`, 프로젝트 `local.properties`, Android Studio 설정, 기본 설치 경로 | 환경변수를 변경하지 않고 기존 값 읽기 |
| NDK | 각 SDK 루트의 `ndk/<version>`, Gradle 구성 | 다른 프로젝트가 사용하는 버전 자동 삭제 금지 |
| Flutter SDK | 실행 파일 위치, `FLUTTER_ROOT`, FVM/Puro/asdf/mise 등 버전 관리자 경로 | SDK의 `bin/cache`와 사용자 데이터 구별 |
| Dart Pub | `PUB_CACHE` 또는 기본 `~/.pub-cache` | 공유 캐시, 재다운로드 비용 안내 |
| Gradle | `GRADLE_USER_HOME`, 프로젝트 wrapper, 기본 `~/.gradle` | 공용 캐시와 프로젝트별 캐시 구별 |
| CocoaPods | `Podfile`, `pod` 실행 파일, CocoaPods 캐시 경로 | Pods 재설치 가능성 확인 |
| SPM | `Package.swift`, `.build`, Xcode DerivedData의 `SourcePackages` | 체크아웃·빌드 데이터 구분 |
| Node 패키지 도구 | lockfile, `npm config get cache`, pnpm/Yarn 설정 | 사용 중인 패키지 매니저별 명령 사용 |
| VS Code / Cursor | 각 `.app`의 번들 경로 및 확장 디렉터리 | `code` CLI가 Cursor를 가리키는 경우 오인 방지 |

실행 파일이 없거나 결과가 불명확하면 **Unknown**으로 기록한다. 사용자 셸의 `PATH`를 조작하지 않으며, 이전 문제처럼 zsh 특수 변수 `path`를 일반 변수로 사용하지 않는다. 외부 명령은 `Process`의 **실행 파일 절대경로 + 분리된 인수 배열**로 실행한다.

## 6. 프로젝트별 정리 규칙

| 플랫폼 | 자동 식별할 생성물 | 기본 조치 |
|---|---|---|
| Android Native | 프로젝트/모듈 `build/`, `.gradle`, `.cxx`, `.externalNativeBuild` | 빌드 출력은 선택 정리, 캐시는 검증 후 |
| iOS Native | DerivedData, 명확한 빌드 출력, SPM `.build`, Pods | DerivedData는 선택 정리, Archives/dSYM은 보존 우선 |
| React Native | `node_modules`, Android 빌드 출력, iOS Pods/DerivedData, Expo 캐시 | 각 항목별 재생성 조건을 보여주고 선택 정리 |
| Flutter | 프로젝트 `build/`, `.dart_tool`, 플랫폼별 빌드 출력, Pub 캐시 | **프로젝트별 `flutter clean` 우선**, 공유 Pub 캐시 별도 관리 |
| Flutter Module | Flutter 모듈과 호스트 Android/iOS 빌드 출력 | 호스트/모듈 종속 관계 파악 후 정리 |
| 공통 | Gradle, CocoaPods, npm, pnpm, Yarn, pip, Homebrew, ccache | 공식 캐시 관리 명령 우선 |

Flutter의 `flutter clean`은 `build/`와 `.dart_tool/`을 정리한다. 따라서 프로젝트마다 별도 빌드 출력 위치를 설정한 경우에도 먼저 Flutter 도구의 동작 범위를 파악한다.

**삭제 금지 기본값:** `.git`, 소스, `pubspec.yaml`, `pubspec.lock`, `Podfile.lock`, `Package.resolved`, Gradle 설정, keystore, provisioning profile, signing certificates, `.env`, 데이터베이스, 사용자가 생성한 아카이브/디버깅 심볼. 임의의 `build`라는 이름만으로 삭제하지 않는다.

## 7. 시스템 자산과 실제 확보 용량

- macOS 설정의 **시스템 데이터**는 단일 폴더가 아니므로, 저장 공간 UI의 카테고리와 `du` 결과가 정확히 대응한다고 주장하지 않는다.
- `/System/Library/AssetsV2/...iOSSimulatorRuntime`는 **읽기 전용 진단**으로 취급한다.
- 런타임 목록과 MobileAsset `Info.plist`의 버전·빌드를 비교해 `Unregistered Asset Candidate`를 표시하되, 시스템 관리 참조 여부를 확정할 수 없는 경우 **직접 삭제 버튼을 제공하지 않는다**.
- `scanBytes`, `logicalBytes`, `allocatedBytes`, `estimatedReclaimableBytes`, `actualReclaimedBytes`를 분리한다.
- APFS clone·hardlink·스냅샷·마운트 중복을 고려하고, 실제 회수량은 **정리 전후 사용 가능한 공간의 차이**로 표시한다.

## 8. 정리 엔진 및 안전장치

```text
Scanner (읽기 전용)
  → Classifier (프로젝트/툴체인 귀속)
  → Policy Engine (Safe / Review / Protected)
  → Preview (대상 경로, 크기, 영향, 재설치 비용)
  → User Approval
  → Preflight (경로 재검증, symlink 확인, 현재 프로세스 검사)
  → Executor (공식 정리 명령 또는 확인된 파일 작업)
  → Verification (가용 공간 변화·오류 기록)
```

- **Safe:** 재다운로드 가능한 캐시. 기본 선택 가능하지만 자동 삭제 기본 OFF.
- **Review:** 프로젝트 빌드 결과, `node_modules`, Pods, NDK, SDK, 확장 구버전. 사용자 개별 승인.
- **Protected:** MobileAsset, 시스템 보호 데이터, Git 저장소, 인증서, 앱의 실제 DB, Docker 볼륨. 정리 금지 또는 공식 앱의 관리 화면 안내.
- 사용자 지정 **Keep Warm** 프로젝트는 빌드 캐시 정리에서 제외한다.
- 정리 대상의 canonical URL을 재확인하고, 분석 후 다른 파일로 바뀐 대상은 정리하지 않는다.
- 휴지통 이동이 가능한 항목은 `FileManager.trashItem` 우선; 공식 캐시 명령으로 영구 삭제하는 경우 사전 고지.
- 삭제 가능 용량은 **추정치**로, 완료 후 실제 회수 용량은 별도로 보여준다.

## 9. 기술 구조

```text
MacStorageDoctorApp (SwiftUI MenuBarExtra + Main Window)
├── Presentation
│   ├── MenuBarOverview / Dashboard / ProjectExplorer
│   ├── ToolchainManager / Cleaner / History / Settings
├── Discovery
│   ├── VolumeInventory / PermissionProbe / SpotlightSeeder
│   ├── FileSystemCrawler / FSEventWatcher / DiscoveryIndex
│   └── ProjectClassifier / WorkspaceResolver
├── ProjectAdapters
│   ├── ReactNativeAdapter / AndroidNativeAdapter
│   ├── IOSNativeAdapter / FlutterAdapter
│   └── HybridProjectResolver
├── ToolchainAdapters
│   ├── Xcode / AndroidSDK / FlutterSDK / Gradle / SPM
│   ├── CocoaPods / NodePackageManagers / IDEs / Unity
├── Storage
│   ├── DirectoryMeter / VolumeMeter / APFSAnalyzer
│   └── SnapshotRepository (SQLite)
├── Cleaner
│   ├── RuleEngine / CleanupPreview / Validator
│   └── SafeExecutor / NativeToolExecutor / AuditTrail
└── Background
    ├── ScanScheduler / FSEventCoordinator / AlertService
    └── LoginItem (SMAppService)
```

### 확장 가능한 핵심 인터페이스

```swift
enum ProjectPlatform: String, Codable {
    case reactNative, expo, androidNative, iosNative, flutter
}

struct DiscoveredProject: Identifiable {
    let id: UUID
    let rootURL: URL
    let platforms: Set<ProjectPlatform>
    let workspaceID: UUID?
    let evidence: [String]
    let confidence: DetectionConfidence
}

protocol ProjectDetector {
    var identifier: String { get }
    func detect(at directory: URL) async throws -> DetectionResult?
}

protocol ArtifactProvider {
    func artifacts(for project: DiscoveredProject) async throws -> [StorageArtifact]
}

protocol CleanupStrategy {
    func preview(_ artifact: StorageArtifact) async throws -> CleanupPreview
    func execute(_ approved: CleanupPreview) async throws -> CleanupResult
}
```

`StorageArtifact`에는 소유 프로젝트, 실제 경로, 공용 여부, 위험도, 소유 툴체인, 추정 회수 공간, 재빌드 비용, 검사 시각과 상태를 기록한다. 공용 SDK나 캐시의 용량을 여러 프로젝트에 **각각 합산하지 않는다**.

### 스캔 성능 정책

- 디스크 여유 공간은 60초마다 가볍게 조회.
- 최초 Full Scan은 진행률·일시정지·취소를 지원.
- 이후 주요 변경을 FSEvents로 감지하고 해당 영역만 재검사.
- 배터리/열/디스크 부하 상태에 따라 속도 제한.
- 스캔 결과는 SQLite로 저장하고 오래된 상세 목록은 집계로 압축.
- 검사되지 않은 범위와 점유량을 숨기지 않는다.

## 10. 수용 기준 및 핵심 테스트

| ID | 검증 시나리오 | 통과 조건 |
|---|---|---|
| DISC-01 | 프로젝트가 `~/Git` 이외의 `~/Documents/work`에 있음 | 수동 경로 설정 없이 발견 |
| DISC-02 | 숨김 폴더 `.workspace/mobile` 내 Flutter 앱 | 발견 |
| DISC-03 | 외장 SSD에 Android 프로젝트 | 볼륨 허용 후 발견, 분리 상태 표시 |
| DISC-04 | React Native 모노레포에 `android/`, `ios/` 포함 | 하나의 앱에 멀티플랫폼 태그, 중복 계산 없음 |
| DISC-05 | Flutter Add-to-App 모듈 | 호스트와 Flutter 모듈의 관계 표시 |
| DISC-06 | `pubspec.yaml`만 있는 순수 Dart 패키지 | Flutter 앱으로 오인하지 않음 |
| DISC-07 | Spotlight 인덱싱 제외 경로 | 전체 크롤에서 발견 |
| DISC-08 | 새 프로젝트 생성 | FSEvents + 부분 재검사로 발견 |
| DISC-09 | 접근 거부 폴더 | 전체 발견 완료로 거짓 표시하지 않음 |
| CLEAN-01 | 무관한 `build` 폴더 | 이름만으로 삭제 제안하지 않음 |
| CLEAN-02 | 실행 중인 Gradle/Xcode/Flutter 작업 | 정리 전 프로세스 및 상태 확인 |
| CLEAN-03 | SDK가 프로젝트 여러 개에 공유됨 | 한 번만 집계, 요구 버전 삭제 보호 |
| CLEAN-04 | `code` 명령이 Cursor를 가리킴 | VS Code와 Cursor를 구분 |
| CLEAN-05 | `PATH`가 비정상 | 앱은 안전하게 오류 처리, 사용자 PATH 변형 없음 |
| CLEAN-06 | 보호된 AssetsV2 잔여 런타임 | 탐지만 수행, 강제 삭제 금지 |
| CLEAN-07 | APFS clone 또는 snapshot | 추정 회수량과 실제 회수량 구분 |

## 11. 개발 로드맵

| 단계 | 목표 | 주요 산출물 |
|---|---|---|
| **MVP 1** | 메뉴바 + 볼륨 상태 + 전체 프로젝트 자동 발견 | Volume Inventory, Crawler, 4종 Detector, Dashboard |
| **MVP 2** | 프로젝트별 생성물 측정 + 안전한 정리 | Artifact Providers, Cleanup Policy, Preview, Verify |
| **v1.0** | Xcode/Android/Flutter SDK·캐시 관리 | Toolchain Manager, NDK/Simulator 탐지, Pub/Gradle 분석 |
| **v1.1** | 지속 감시 + 개발자 특화 자동화 | FSEvents, History, Notifications, Keep Warm |
| **v1.2** | 시스템 캐시 및 통합 저장공간 관리 | 안전한 OS/앱 캐시 정리, 전체 작업 기능 대응, APFS/AssetsV2 진단, 권한/작업 보고서 |

## 12. 구현상 최종 결정

1. **사용자가 프로젝트 루트를 일일이 입력하지 않아도 된다.** 최초 실행에서 접근 가능한 로컬 디스크를 자동 탐색한다.
2. **RN, Android Native, iOS Native, Flutter를 동등한 1급 지원 대상으로 다룬다.** 모노레포와 혼합 프로젝트는 중복 집계하지 않는다.
3. **프로젝트 폴더와 공용 툴체인 디렉터리를 각각 자동 발견한다.** 설치 경로를 `~/Git` 또는 기본 SDK 경로로 고정하지 않는다.
4. **Spotlight는 빠른 후보 수집 수단이고, 파일시스템 크롤이 실제 발견의 기반이다.** FSEvents는 발견 후 변화 추적에 활용한다.
5. **권한이나 오프라인 볼륨으로 접근 불가능한 영역은 발견하지 못했다고 명시한다.** '모든 파일 발견'이라는 과장된 완료 상태를 표시하지 않는다.
6. **macOS가 보호하는 시스템 자산은 진단만 한다.** 안전성이 입증되지 않은 강제 삭제 기능은 제공하지 않는다.
7. **정리의 성공은 사전 예상 GB가 아니라 정리 후 실제 여유 공간 증가로 검증한다.**

## 13. v1.2 핵심 요구: 지금까지 수행한 **모든** 작업을 GUI로 재현

**완성 기준은 특정 개발 프레임워크를 지원하는 것만이 아니다.** 사용자가 터미널에서 직접 수행했던 `df`·`du` 검사, 개발 프로젝트 자동 탐색, 시스템 자산 확인, 앱 데이터 분류, 안전한 정리, 정리 후 실제 여유 공간 검증까지 앱 내부에서 수행해야 한다. 기존 도구가 지원하는 작업은 직접 실행하며, macOS 정책상 불가능하거나 위험한 작업은 **검사 및 공식 관리 경로 안내**를 제공한다. 이를 동일한 '정리 버튼'으로 취급해서는 안 된다.

### 13.1 모든 과거 작업의 기능 대응표

| ID | 수동 작업/진단 항목 | 앱에서 제공할 기능 | 동작/안전 등급 |
|---|---|---|---|
| HIST-01 | `df -h /`, `df -h /System/Volumes/Data` 비교 | **Disk Overview**: APFS 시스템·데이터 볼륨과 공유 컨테이너 표시 | 자동 검사/읽기 |
| HIST-02 | `du -sh`, `du -d 1/2`, `sort -h` | **Storage Explorer**: 폴더별 계층, 크기 정렬, 대용량 항목 | 읽기 |
| HIST-03 | `du -x`로 시뮬레이터 마운트 중복 제거 | **Filesystem Boundary Guard**: 동일 마운트·볼륨 중복 제외 | 읽기 |
| HIST-04 | `df` 323GiB vs `du` 300G 차이 분석 | **Accounting Inspector**: 파일 합계·볼륨 사용량·분석 누락·추정 불확실성 분리 | 읽기/차이 원인 확정 불가 표시 |
| HIST-05 | macOS '시스템 데이터' 236GB→202GB 의문 | **System Data Explorer**: 시스템 분류값과 파일 분석값은 다름을 안내, 상관 후보 표시 | 읽기/동일값 재현 보장 금지 |
| HIST-06 | Time Machine `tmutil listlocalsnapshots /` | **Snapshot Inspector**: 로컬 백업 스냅샷 | 읽기/공식 관리 유도 |
| HIST-07 | `diskutil apfs listSnapshots` | **APFS Snapshot Inspector**: 데이터/시스템 볼륨 각각 검사 | 읽기/직접 삭제 기본 금지 |
| HIST-08 | `/private/var`와 `/Library` 조사 | **System Directory Analyzer** | 읽기/제한된 정리 |
| HIST-09 | `/System/Library/AssetsV2` 37GB | **Apple MobileAsset Scanner**: 유형별 크기 분석 | 읽기 전용 |
| HIST-10 | 18.2·18.4 잔여 `.asset` 16.9GB 파악 | **Orphan Runtime Candidate Detector**: plist 버전·빌드 ↔ simctl 비교 | 진단 전용, 제거 불가 표시 |
| HIST-11 | `xcrun simctl runtime list` | **Simulator Runtime Manager** | 공식 CLI 상태 조회 |
| HIST-12 | `xcrun simctl list devices` | **Simulator Device Manager** | 공식 CLI 조회 및 명시적 삭제 |
| HIST-13 | `simctl delete unavailable` | **Unused Simulator Device Cleanup** | 개별 승인 후 공식 CLI |
| HIST-14 | Xcode Components 런타임 제거 | **Xcode Runtime Actions**: 지원되는 공식 제거 기능/설정 연결 | 개별 승인/관리 기능 우선 |
| HIST-15 | DerivedData·Archives·DeviceSupport 조사 | **Xcode Storage**: 각 항목 크기 및 프로젝트 귀속 | 빌드 캐시는 조건부 정리; Archives/dSYM 보존 |
| HIST-16 | SDK/NDK 설치 7개 버전 분석 | **NDK Manager**: 전체 설치 인벤토리·버전별 크기 | 읽기 |
| HIST-17 | 여러 Gradle `ndkVersion` 파악 | **NDK Dependency Resolver**: 프로젝트 의존성 그래프 | 읽기, unknown 표시 |
| HIST-18 | NDK 전체 삭제 후 빌드 시 재설치 | **NDK Bulk Cleanup**: 명시적 전체 선택과 다음 빌드 영향 안내 | 승인 필수, SDK 공식 도구 |
| HIST-19 | NDK/SDK 재설치, 라이선스 | **NDK Restore Assistant**: SDK 경로·설치·라이선스 상태·필요 버전 | 공식 도구, 승인 필수 |
| HIST-20 | Android `system-images` 10GB | **AVD & SDK Image Manager**: API/ABI별 시스템 이미지 | 공식 SDK 관리 도구 |
| HIST-21 | `~/.android` 가상 기기 6.5GB | **Android Virtual Device Inspector** | 공식 AVD 삭제/데이터 초기화 |
| HIST-22 | Gradle `~/.gradle` 9.2GB | **Gradle Cache Inspector**: wrapper/daemon/modules/build-cache 분리 | 제한적 정리, 프로젝트 의존성 고려 |
| HIST-23 | npm/CocoaPods/pip/ccache 정리 | **Package Cache Cleaner** | 공식 캐시 명령으로 승인 후 |
| HIST-24 | Yarn/pnpm/Flutter Pub/SPM 캐시 | **Package Cache Cleaner** 확장 | 버전·프로젝트 구별, 승인 후 |
| HIST-25 | `~/Git` 전체에서 `node_modules`, Pods, build 탐색 | **Project Artifact Discovery**: 전체 접근 가능 볼륨·중첩 프로젝트 | 자동 발견/중복 배제 |
| HIST-26 | RN·Expo 빌드 산출물 정리 | **RN/Expo Project Cleaner** | 프로젝트별 선택, 재설치 설명 |
| HIST-27 | Android Kotlin/Java 빌드 산출물 | **Native Android Cleaner** | 프로젝트별 Gradle/CMake 산출물 |
| HIST-28 | iOS Native 빌드·SPM | **Native iOS Cleaner** | DerivedData/SwiftPM, 소스·서명 보존 |
| HIST-29 | Flutter `build`, `.dart_tool`, Pub | **Flutter Cleaner**: `flutter clean` 및 캐시 | 공식 도구, 프로젝트별 |
| HIST-30 | `code` 실행 시 Cursor를 가리킨 오류 | **IDE Identity Validator**: 실행 앱 번들ID·절대경로·실제 확장 루트 | 진단/오인 방지 |
| HIST-31 | VS Code 확장 9.7GB, ChatGPT 구버전 다수 | **Extension Version Cleaner**: 활성/구버전/프로필 비교 | 승인 후 선택 정리/휴지통 |
| HIST-32 | Cursor·VS Code 앱 지원 데이터 3~8GB | **IDE Data Breakdown**: workspaceStorage/globalStorage/캐시 분류 | 앱 상태·설정 보존, 제한적 정리 |
| HIST-33 | Notion 12GB, Slack/Discord/Chrome 등 | **Application Cache Inspector**: 앱별 지원 데이터와 캐시 구별 | 앱 데이터는 보호, 공식 UI 우선 |
| HIST-34 | Containers 19GB, KakaoTalk 5.4GB, CoreDevice 4.3GB | **Container Explorer**: 앱 소유자·크기·보호 데이터 경고 | 기본 진단만 |
| HIST-35 | `/Library/Caches`, `~/Library/Caches` | **System & App Cache Cleaner**: 안전한 세부 항목만 | 화이트리스트/권한 승인 |
| HIST-36 | `/private/var/vm`, `/private/var/folders`, 시스템 로그 | **System Cache Inspector**: 크기·유형·재생성 여부 안내 | 보호/자동 삭제 금지 |
| HIST-37 | Homebrew `/opt` 16GB | **Homebrew Inspector**: brew cache, cleanup 예측/실행 | `brew cleanup -n` 후 승인 |
| HIST-38 | Unity 2022.3/6000.3 Editor 20GB | **Unity Version Manager**: 프로젝트 버전 매칭 및 Hub 연결 | 앱 공식 제거 방식 |
| HIST-39 | DiffusionBee/ComfyUI/Z-Image 모델 파일 | **AI Asset Explorer**: 모델·체크포인트·중복 후보 | 사용자 자료 보호, 수동 선택 |
| HIST-40 | 파일 정리 후 29→111GiB 증가 | **Actual Reclaim Verifier**: 전후 공간 비교·로그·성공 여부 | 사전 추정과 실측값 별도 |
| HIST-41 | `env: sh: No such file or directory` 발생 | **Tool Environment Diagnostics**: PATH·SDK 변수·CLI 가용성 확인 | READ ONLY, 쉘 설정 자동 변경 금지 |
| HIST-42 | 비정상 `PATH`의 원인(`path` zsh 특수 배열) | **Shell Config Assistant**: 안전한 변경 제안, 복사 가능 수정 안내 | 설정 파일 임의 변경 금지 |
| HIST-43 | `~/Documents` 979MB vs '문서' 111GB | **Category Explanation**: Finder 문서 폴더≠macOS 문서 카테고리 | 진단/설명 |
| HIST-44 | 프로젝트 밖의 대용량 앱·데이터 찾기 | **Whole-Disk Large Item Finder**: Downloads, Applications, 보조 볼륨 포함 | 읽기/개별 선택 |
| HIST-45 | 정기 캐시 점검 스크립트 | **Periodic Monitoring**: 주기·임계값·변화량 기록 | 자동 점검/기본 자동 삭제 OFF |

**완료 정의:** 위 표의 모든 행이 출시 전 QA 체크리스트에서 `지원`, `공식 앱으로 연결`, `진단 전용(보호 정책)` 중 하나로 명시되어야 한다. 단순히 '분석 대상'이라고 적힌 것을 실질적인 자동 삭제 지원으로 간주하지 않는다.

## 14. 시스템 캐시 정리 설계 — 일반 사용자 캐시와 OS 보호 자산을 분리

### 14.1 4단계 캐시 분류 체계

| 단계 | 대표 경로·콘텐츠 | 기본 정책 | UI 표시 |
|---|---|---|---|
| **A. Safe / 앱 캐시** | 사용자 홈의 일부 `~/Library/Caches/<identified-app>`, npm/pip/CocoaPods/ccache/Homebrew 캐시 | 공식 명령/정확한 캐시 경로만, 검증 후 사용자 승인 | **정리 가능** |
| **B. Conditional / 재생성 가능한 시스템 연관 캐시** | 확인된 앱별 `/Library/Caches/<bundle-id>` 일부, 명확히 앱 소유인 로그, Xcode DerivedData, Spotlight/QuickLook의 공식 재생성 관리 대상 | 해당 소유 앱 정지·관리 API·권한 확인 후 조건부; 지원되지 않으면 안내 | **확인 후 정리** |
| **C. Managed / OS가 관리** | `/System/Library/AssetsV2`, 업데이트 파일, macOS의 purgeable space, 시스템 프레임워크 캐시, CoreDevice 관리 데이터, 일부 `private/var` 데이터 | 진단하고 **macOS/Xcode 공식 관리 기능으로만 조치**; 수동 강제 삭제 없음 | **시스템 관리 / 직접 정리 불가** |
| **D. User Data / 캐시로 보일 수 있는 실제 데이터** | `Application Support/Notion`, KakaoTalk/Slack/Discord 대화·첨부, 브라우저 프로필, Docker volumes, 프로젝트 `.git`, 인증서·키체인 | 앱별 정상 삭제 흐름 또는 보존; 폴더 일괄 삭제 금지 | **사용자 데이터 보호** |

### 14.2 System Cache Manager 실제 동작

1. 스캔에서 `~/Library/Caches`, `/Library/Caches`, `~/Library/Logs`, `/private/var`, `/System/Library/AssetsV2`, `/Library/Developer`, 각 사용자 컨테이너의 **알려진 캐시 부분**을 별도 인벤토리화한다.
2. 각 항목은 `owner(bundleID/process/tool)`, `path`, `size`, `lastModified`, `volumeID`, `fileID`, `cleanupMethod`, `risk`, `reason`, `scanCoverage`를 가진다.
3. 등록된 정책이 없는 파일은 **절대 캐시라고 추정해서 삭제하지 않는다**. 대용량으로 보이더라도 `검토 필요`로만 표시한다.
4. `Safe` 그룹에서는 **삭제 가능한 개별 캐시만 사전 선택**한다. 시스템 전체의 `Caches` 디렉터리는 정리 단위가 될 수 없다.
5. `Conditional`에서는 해당 앱 종료/실행 중인 작업, 업데이트 중인지, 원본 재다운로드 가능성, 앱 권한, 스냅샷을 확인한 뒤 체크박스를 제공한다.
6. `Managed`에서는 '공식 관리 화면 열기', '버전 진단', '문제 보고서 내보내기'만 제공한다. 관리자 권한·Full Disk Access가 있어도 SIP 보호 영역 삭제 기능은 제공하지 않는다.
7. 작업 후 전후 가용 공간을 측정해 실제 증가량을 보여준다. 휴지통에 넣은 파일은 **휴지통을 비우기 전까지 미회수**로 표시한다.

### 14.3 OS 및 시스템 데이터 화면 예시

```text
System & App Cache Center

System Data Explanation
  macOS '시스템 데이터'는 별도 폴더가 아닌 분류값입니다.
  파일시스템 측정값과 일치하지 않을 수 있습니다.

[Cleanable Now]
  □ CocoaPods downloads                         5.7 GiB
  □ npm cache                                   5.5 GiB
  □ VS Code C++ IntelliSense cache             3.8 GiB

[Review Required]
  □ Identified app cache: Chrome               5.0 GiB
  □ Old Android build outputs                 10.5 GiB

[Managed by macOS — Diagnose Only]
  ● MobileAsset iOS 18.2 unregistered           8.4 GiB
  ● MobileAsset iOS 18.4 unregistered           8.5 GiB
  ● APFS / Time Machine snapshots             Checked
  ● VM swap / system caches                   Protected

[Protected User Data]
  ● Notion Application Support                 12.0 GiB
  ● KakaoTalk Container                         5.4 GiB

[ Analyze ]  [ Review Selection ]  [ Open Official Manager ]
```

숫자는 실제 대화에서 확인한 과거 시점의 **예시**로만 쓰고, 실행 시 현재 스캔 결과를 필수로 재검증한다. `Cleanable Now`에 포함된 항목도 실제 환경에서 감지되어야 한다.

### 14.4 OS별 숨김 데이터/캐시의 정확한 취급

- `/System/Library/AssetsV2`는 **macOS 관리 자산**: 읽기 전용 진단. 등록되지 않은 iOS Runtime이 감지되더라도 자체 제거하지 않는다.
- `/private/var/vm`은 VM·swap 데이터: 강제 삭제 금지. 재부팅이나 macOS 자체 관리 동작은 사용자가 선택하며 앱이 자동 수행하지 않는다.
- `/private/var/folders`는 앱/시스템 임시 데이터가 혼재: 전체 삭제 금지. 개별 파일도 등록된 공식 정리 방법 없이 삭제하지 않는다.
- `/Library/Caches`: 읽기 가능하고 소유자가 분명한 **등록된** 캐시만 제한적 정리. 관리자 권한이 필요하면 실제 작업 전 별도 확인하며, 기본 릴리스에서는 관리자 쓰기 기능을 비활성화한다.
- `~/Library/Caches`: 앱 실행 상태·파일 변경 여부·캐시 소유자를 검증한 뒤 일부만 정리한다. 브라우저 인증·오프라인 데이터·앱 상태 폴더는 제외한다.
- `~/Library/Application Support`, `~/Library/Containers`: 캐시와 사용자 데이터가 섞일 수 있어 **전체 디렉터리 일괄 삭제 금지**. Notion/Slack/Discord/Chrome/KakaoTalk 등은 내부 하위 캐시가 명확할 때만 제안하고, 필요한 경우 해당 앱의 공식 저장공간 관리 UI를 연다.
- `~/Library/Developer`, `/Library/Developer`: DerivedData 등 확인된 개발 산출물만 정리하고, CoreSimulator 관리 캐시나 DeviceSupport는 도구/런타임 상태 확인 후 처리한다.
- Spotlight 인덱스·시스템/보안 로그·업데이트 파일: 단순 용량 확보를 목적으로 일괄 초기화하지 않는다. 공식 OS 조치 방법만 안내한다.
- APFS/Time Machine 스냅샷: 발견·생성 시점·볼륨을 표시하고, 지원되는 관리 도구의 동작과 영향을 설명한다. **스냅샷 직접 삭제는 MVP에서 제외**한다.

## 15. 사용자 여정: “분석부터 실제 회수까지” 한 번에

### 15.1 메뉴바 팝오버

```text
┌────────────────────────────────────────────────────────┐
│  ◉ Mac Storage Doctor                           ⚙    │
│                                                        │
│  111 GiB available                 75% volume usage    │
│  ████████████████████░░░░░░░                          │
│                                                        │
│  Current results · Updated 4 min ago                   │
│    Safe cache cleanup candidate           7.2 GiB     │
│    Developer cleanup candidate           12.4 GiB     │
│    Protected/managed assets              16.9 GiB     │
│                                                        │
│  [Quick Optimize]         [Analyze Everything]         │
│                                                        │
│  Projects: 43    Scan coverage: Partial (2 paths)      │
└────────────────────────────────────────────────────────┘
```

### 15.2 `Quick Optimize`의 동작

- 백그라운드 퀵 스캔 후 기본 `Safe` 대상만 표시하며 **확인 화면 없이 삭제하지 않는다**.
- `Safe` 항목을 선택하여 Preview → Confirm → Cleanup → Verify 진행.
- `Developer Clean`에는 빌드/의존성/SDK 버전 삭제가 있으므로 앱·프로젝트·재설치 비용을 별도 표시.
- `System Managed`는 검사 결과만 보여준다. **Quick Optimize 합계에 포함하지 않는다**.
- `Automatic` 설정은 검사/알림만 기본 활성화. 무인 캐시 삭제는 기본 OFF이며 향후 별도 옵트인으로 설계한다.

### 15.3 상세 창 네비게이션 수정

1. **Overview** — APFS 볼륨과 실제 가용 공간, 지난 기간 변화, 카테고리 설명
2. **Space Map** — 전체 접근 가능 디스크/앱/숨김 폴더 크기 트리, Treemap, 상위 디렉터리
3. **System & App Caches** — 일반 캐시와 macOS 관리 자산 구분, 공식 조치 연동
4. **Projects** — RN/Android/iOS/Flutter 프로젝트 자동 발견 및 Keep Warm
5. **Toolchains** — Xcode/Simulator, Android/NDK, Flutter SDK, Unity/VS Code/Cursor 등
6. **Smart Cleaner** — 위험 등급별 후보, Preview, 실제 실행, 검증
7. **History** — 용량 변화/점유 증가율/정리 전후/진단 보고서
8. **Settings & Permissions** — 자동 점검, 제외 영역, 파일 접근 허용, 경고 임계값

## 16. 실행 엔진: 안전·권한·오류 정책

### 16.1 Cleanup Operation 명세

```swift
enum CleanupCapability: String, Codable {
    case executable         // 앱이 공식 도구/검증된 파일 작업으로 직접 수행
    case userApprovalNeeded // 실행 전 영향·재설치 비용·대상 선택 승인
    case officialAppOnly    // Xcode/Android Studio/Unity Hub 등 공식 화면으로 이동
    case readOnlyDiagnosis  // 시스템 보호 자산: 검사 결과/보고서만 제공
}

enum StorageCategory: String, Codable {
    case applicationCache, systemRelatedCache, protectedSystemAsset
    case projectBuild, projectDependency, installedToolchain
    case userData, apfsSnapshot, unknown
}

struct CleanupCandidate: Identifiable, Codable {
    var id: UUID
    var source: URL
    var toolID: String?
    var owningProjectID: UUID?
    var category: StorageCategory
    var capability: CleanupCapability
    var estimatedReclaimBytes: Int64?
    var requiresDownloadAfterward: Bool
    var requiresRebuildAfterward: Bool
    var reason: String
    var policyID: String
    var scanTimestamp: Date
}
```

### 16.2 안전 정책

- 모든 삭제 작업은 **경로 allowlist + 대상 종류 allowlist + `lstat`/volumeID/fileID 확인**을 통과해야 한다.
- `realpath`/canonical URL을 확인하고 심볼릭 링크·상위 디렉터리 전환·TOCTOU 경로 변경을 감지하면 거부한다.
- 전체 홈, 프로젝트 루트, `/System`, `/private`, `/Library`, `/Applications`, `~/.ssh`, Keychain, git objects 등 최상위·보호 경로를 일괄 삭제 대상으로 허용하지 않는다.
- `Process`는 절대경로 실행 파일과 분리된 인자 배열 사용. `sudo sh -c`, 사용자 문자열 셸 치환은 사용하지 않는다.
- `code`가 Cursor를 가리키더라도 번들ID·앱 경로로 검증한다. `sdkmanager`와 새로운 Android CLI 중 **실제 설치된 지원 도구**에 맞는 명령을 선택한다.
- `PATH`·`NDK_HOME`·`ANDROID_HOME` 등 사용자 환경변수는 **읽기 전용 검사**하며, 정리 과정에서 영구 변경하지 않는다. 검사/실행 프로세스 전용 환경만 생성한다.
- 관리자 권한 요구 시엔 최소 권한으로 세분화한다. 일반 캐시는 관리자 권한 없이 동작하며, Full Disk Access는 사용자가 시스템 설정에서 선택한다. **FDA가 SIP 해제를 뜻하지 않는다.**
- 공식 관리 명령이 실패하면 우회 삭제하지 않고 실패 내용·관리 화면 연결·재시도 정보를 표시한다.
- 정리 로그는 실행된 공식 작업, 종료 코드, 삭제 대상 ID, 사전/사후 용량, 검증 상태를 저장한다. 개인 경로는 공유 리포트에서 마스킹한다.

### 16.3 프로세스/작업 상태 검사

- Xcode 빌드, `xcrun simctl`, Gradle daemon/빌드, Android Emulator, Flutter, npm/pod 설치, Unity 편집기, VS Code/Cursor 확장 업데이트 등이 실행 중이면 해당 항목을 작업 잠금 처리하거나 명시적으로 중단 선택을 요구한다.
- 프로그램이 임의로 작업을 `kill -9`하지 않는다.
- SDK 전체 제거 후 필요한 버전 자동 재설치가 항상 보장되는 것은 아니므로, `sdkmanager`/Android CLI가 사용할 SDK root, 라이선스, 네트워크, 빌드 요구사항을 검사한다.

## 17. 스토리지 진단 알고리즘 상세

### 17.1 볼륨 우선 진단

```text
APFS Container / Volumes
  → Root / Data volume distinction
  → Capacity / Available / Purgeable (available APIs where supported)
  → Mounted volume identity, snapshots, firmlinks
  → Top directory tree (do not cross file system boundary)
  → Per-project + per-app + shared caches classification
  → Unscanned coverage and estimated accounting discrepancy
```

- 서로 다른 시점에 수집한 `df`, `du`, 설정 앱 카테고리 수치를 합산하지 않는다.
- `df` 전체 볼륨 사용량과 `du` 탐색 파일 크기의 차이는 **원인 불명 상태로 표시**할 수 있어야 한다. 접근 누락, 메타데이터, 공유 블록, 파일시스템 운영 방식 등 가능한 이유를 정보 패널에 설명한다.
- '시스템 데이터'는 Apple의 저장 공간 카테고리이며 하나의 삭제 가능한 데이터 모음이 아니다. GUI에 카테고리 값을 직접 가져오는 **문서화된 안정적 API가 없으면**, 앱 자체의 추정치임을 분명히 표시하고 Apple과 동일하다고 주장하지 않는다.
- `du -x`와 같은 마운트 경계 보호 및 동일 파일 식별 기능을 고유 파일 탐색 엔진에 구현한다.
- `df` 여유 공간의 개선은 실측 결과로 기록하지만, APFS의 동적 공간·다른 앱의 동시 쓰기로 인해 순수 삭제량과 반드시 같지는 않다고 설명한다.

### 17.2 저장 공간 히스토리

- Capacity: 60초마다 경량 API로 샘플링.
- Cache inventory: 하루 1회 또는 변경 감지 시.
- Full scan: 주 1회 혹은 사용자가 지정한 시간, 최초 스캔은 수동 시작 가능.
- 보관: 일별 상세 30일, 주별 12개월, 그 이전 월별 집계.
- 비교: 볼륨 이용가능 공간 증가/감소, 프로젝트 캐시 증감, 시스템 자산 증가, 신규 도구 및 SDK 설치 이벤트.
- 알림: 20GiB Critical, 50GiB Warning 등 설정 가능. 동일 사건 재통지는 일정 시간 억제.

## 18. 자동 프로젝트·도구 탐색과 시스템 데이터 통합

시스템 캐시도 프로젝트 소유 관계를 이해할 수 있어야 한다. 예를 들어 `~/Library/Developer/Xcode/DerivedData/<hash>`는 가능하면 Xcode 프로젝트의 `WorkspacePath` 또는 `ProjectPath`와 연결하고, Android SDK의 NDK 버전은 실제 프로젝트별 요구 버전과 연결한다.

- **Shared Storage:** NDK, SDK system image, Gradle dependencies, CocoaPods cache, Flutter SDK 등은 프로젝트에 중복 합산하지 않고 '공용 툴체인'으로 표시한다.
- **Project Storage:** `build/`, `.dart_tool`, `node_modules`, Pods 등은 해당 프로젝트에 연결한다. 프로젝트 아티팩트가 심볼릭 링크를 통해 공용 스토어를 가리키면 추가 용량으로 중복 계산하지 않는다.
- **App Storage:** Notion, VS Code, Cursor, Chrome, Discord, Slack, KakaoTalk, Docker, Unity 등은 번들ID/소유 앱과 연결하되 내용이 불명확하면 사용자 데이터로 보호한다.
- **System Storage:** AssetsV2, VM, 시스템 업데이트 파일, APFS snapshots은 별도 카테고리에서 시스템 자체의 관리 항목임을 표시한다.

## 19. 새 수용 기준 (v1.2 필수 QA)

| ID | 필수 시나리오 | 통과 조건 |
|---|---|---|
| SYS-01 | 37GB AssetsV2 중 33GB iOSSimulatorRuntime | 유형/버전/빌드별 크기 표시 |
| SYS-02 | 제거된 iOS 18.2/18.4의 `.asset`만 남음 | `Unregistered Asset Candidate`, **삭제 액션 없음** |
| SYS-03 | `/Library/Developer` 일반 `du` 112GB vs `du -x` 17GB | 마운트된 시뮬레이터 중복을 설명, 중복 집계 방지 |
| SYS-04 | APFS Data 볼륨 스냅샷 0개 | '없음'으로 표시, 타 볼륨과 혼동 금지 |
| SYS-05 | `df` 323GiB와 `du` 300G | 23GiB를 자동으로 특정 파일이라고 단정하지 않음 |
| SYS-06 | Notion Application Support 12GB | 캐시로 단정/기본 삭제하지 않음 |
| SYS-07 | KakaoTalk Container 5.4GB | 메시지/첨부 파일 보존, 앱 데이터 보호 |
| SYS-08 | `/private/var/vm`가 거대함 | 보호 안내, `rm -rf` 호출 없음 |
| SYS-09 | `/Library/Caches` 속 식별되지 않은 항목 | 전체 삭제하지 않고 조사 상태 유지 |
| SYS-10 | npm/CocoaPods/pip/ccache 캐시 정리 | 공식 캐시 도구 실행, 종료 코드와 실제 용량 변동 기록 |
| SYS-11 | NDK 7개 버전 전체 제거 | 영향 승인, SDK 명령 확인, 프로젝트별 복원 안내, PATH 유지 |
| SYS-12 | NDK 28 요구 프로젝트에 28 미설치 | 누락 경고, 자동 재설치 보장이라고 오인하지 않음 |
| SYS-13 | zsh 특수 `path` 변수 실수 시뮬레이션 | 앱 프로세스와 사용자 PATH 오염 없음 |
| SYS-14 | VS Code CLI `code`가 Cursor로 연결 | 두 앱 확장 분석 분리 |
| SYS-15 | Flutter 프로젝트 위치가 `~/Git` 밖 | 권한 있는 전체 탐색에서 발견, `flutter clean` 작업 제안 |
| SYS-16 | iOS Swift 네이티브 프로젝트에서 DerivedData 큼 | Xcode 데이터 탐지, 아카이브/심볼 무단 삭제 없음 |
| SYS-17 | 여러 RN+Android+iOS/Flutter 모듈 포함 | 프로젝트·공유 아티팩트 중복 집계 없음 |
| SYS-18 | 앱 실행 중 Caches에 파일 쓰기 | 실행 상태 감지, 위험 항목 차단/보류 |
| SYS-19 | 정리 후보를 휴지통으로 이동 | 실제 확보 공간은 휴지통 비우기 전 '미회수' 표시 |
| SYS-20 | 디스크 일부 권한 없음 | 검사 범위, 누락된 항목, FDA 안내 표시 |
| SYS-21 | 디스크 여유 공간이 111GiB | 로그와 트렌드에 실측치로 기록 |
| SYS-22 | 자동 스캔 도중 앱 종료/재시작 | 취소·복구 가능, 재시도, 중복 삭제 없음 |
| SYS-23 | 지원되지 않는 시스템 파일 정리 요청 | 불가능 사유와 공식 도구 안내, 위험한 대체 명령 제공하지 않음 |

## 20. 단계별 출시 계획과 DoD

**이번 요구 범위는 최종 제품의 필수 범위**이지만, 위험한 시스템 파일의 삭제 지원까지 요구하는 것은 아니다. '모든 행동 지원'은 **실제 정리가 가능한 것은 안전하게 앱에서 수행하고, 관리 영역은 같은 UI에서 원인을 진단하고 공식 관리 도구로 이어주는 것**으로 정의한다.

| 단계 | 범위 | 완료 조건 |
|---|---|---|
| **Foundation** | SwiftUI 메뉴바, APFS 용량, SQLite 기록, Scan/Preview/Verify, 자동 폴더 발견 | 권한 있는 내부 볼륨에서 RN/Android/iOS/Flutter 발견 |
| **System Analyzer** | `df`/`du` 상당 GUI, Data/System/APFS 구분, AssetsV2, 스냅샷, `/private` 분석, 시스템 데이터 설명 | 이번 202GB 조사 단계 GUI로 재현 |
| **Safe System & Cache Cleaner** | 사용자 캐시, 확인된 앱 캐시, 공식 패키지 캐시, 로그 등 | 작업 전후 실측·보호 정책·승인·검증 |
| **Developer Cleaner** | Simulator, NDK/SDK/AVD, Xcode, Gradle, CocoaPods, RN/Android/iOS/Flutter, VS Code/Cursor, Unity | 사용·미사용 분석과 공식 관리자 연동 |
| **Automation & Polish** | FSEvents 증분 검사, 히스토리, 로우 스페이스 알림, 보고서, 프로그램 공증 | 배터리/CPU/권한 예외/업그레이드 테스트 완료 |

### 가장 중요한 제품 약속

1. **전체 자동 발견:** 사용자 입력 폴더에 의존하지 않는다. 단, 권한·오프라인·네트워크 경계를 정직하게 표시한다.
2. **시스템 캐시 지원:** 시스템 관련 캐시까지 스캔하되, 삭제는 소유자가 확인된 안전한 항목으로 제한한다.
3. **과거의 모든 정리 작업 UI화:** 단순 조회뿐 아니라 실제 삭제·재설치·공식 관리 화면 연결·실측 검증까지 제공한다.
4. **삭제보다 정확한 판단 우선:** 사용 중인 SDK·모델·앱 데이터·시스템 자산은 보존하고 조건을 충족한 파일만 삭제한다.
5. **일반 사용자도 이용 가능:** 개발 도구를 설치하지 않은 Mac에서도 시스템/앱 캐시 분석과 저장 공간 모니터링이 작동한다.

## 공식 구현 참고 자료

- Apple macOS 저장 공간(시스템 데이터 정의): https://support.apple.com/ko-kr/guide/mac-help/mchl3d437fbc/27/mac/27
- Apple SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice
- Android SDK Manager: https://developer.android.com/tools/sdkmanager
- Flutter CLI (`flutter clean`): https://docs.flutter.dev/reference/flutter-cli

- Apple FSEvents: https://developer.apple.com/documentation/coreservices/file_system_events
- Apple File System Events Programming Guide: https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/index.html
- Android Studio 프로젝트 구조: https://developer.android.com/studio/projects/
- Flutter pubspec 구조: https://docs.flutter.dev/tools/pubspec
- Flutter CLI (`flutter clean`): https://docs.flutter.dev/reference/flutter-cli
