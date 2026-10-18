# 설계 대비 구현 현황

이 문서는 원본 설계의 요구사항과 현재 코드를 구분합니다. UI에 존재하는 메뉴만으로 기능 완료를 판정하지 않습니다.

| 설계 범위 | 현재 상태 | 남은 작업 |
|---|---|---|
| 메뉴바 / Overview | 상주 메뉴바, 표시 전환·저용량 경고, 로그인 항목 설정 | 용량 시계열 차트 |
| 전체 볼륨 프로젝트 탐색 | 기본 구현 | Spotlight 가속, 클라우드·오프라인 상세 인벤토리, 대규모 디스크 성능 QA |
| 프로젝트 분류 | 기본 구현 | YAML 전체 파서, Gradle 간접 설정 해석, 모노레포/하이브리드 그래프 정교화 |
| 용량 측정 / Space Map | 구현 | 실제 treemap, 볼륨 단위 글로벌 hardlink accounting, clone 공유 블록 추정 |
| 시스템 데이터 설명 | 구현 | APFS 컨테이너 관계, 누락과 사용량 차이의 구조화 진단 |
| SQLite 이력 | 구현 | 30일/주별/월별 보관·압축, 용량 샘플 영속화 |
| Safe / Review / Managed / Protected | 구현 | 앱별 세부 allowlist; 현재 Safe 직접 실행 정책 없음 |
| DerivedData 정리 | 제한 구현 | 경합 없는 descriptor 기반 이동, 실사용 휴지통 복원 QA |
| 패키지 캐시 공식 명령 | 안내만 제공 | npm/pip/pod/brew/pnpm 등 검증·preview·실행 어댑터 |
| Flutter / Android / RN 프로젝트 정리 | 분석·안내 | 공식 도구 실행과 재설치 조건 검증 |
| SDK / NDK | 설치 목록·직접 ndkVersion 진단 | SDK root 연계, 동적 Gradle 변수·카탈로그, 삭제·복원·라이선스 |
| Simulator | 공식 읽기 조회 / Xcode 연결 | 개별 기기·런타임 제거 승인 흐름 |
| MobileAsset | 버전·빌드·용량 측정, 삭제 없음 | simctl 등록 정보와 대조, 접근 오류 구조화 |
| VS Code / Cursor | bundle ID 구별·확장 폴더 측정 | 활성 프로필/구버전 확장 판정·정리 |
| Unity / AI 모델 | 설치 경로·보호 앱 데이터 진단 | 프로젝트 버전 의존성, 모델 전용 탐색 |
| FSEvents / 자동화 | 실행 중 증분 재검사, 일일 quick scan, 유실·재시작 복구 안내 | 재시작 간 이벤트 이력 재생, 배터리/I/O 정책, 알림 |
| 배포 | Universal .app/.pkg, GitHub 태그 릴리스, 서명·공증 자동화 경로 | 인증서 등록 후 서명·공증 실검증, 설치·업그레이드 QA |

## HIST 대응표

- HIST-01–05: 볼륨 용량·폴더 측정·마운트 경계·차이 설명 기본 지원. 컨테이너 관계 정밀 분석은 남음.
- HIST-06–07: diskutil/tmutil 결과 조회. 스냅샷 삭제 없음.
- HIST-08–10: 시스템 경로와 MobileAsset 측정. 미등록 런타임 확정/참조 대조 미구현.
- HIST-11–12: simctl list 조회.
- HIST-13–14: Xcode 연결. 앱 자체 삭제 실행 미구현.
- HIST-15: DerivedData 제한 정리, Archives/DeviceSupport 진단.
- HIST-16–17: NDK 목록 및 직접 지정 버전 진단. 모든 Gradle 해석은 지원하지 않음.
- HIST-18–21: SDK/AVD 용량 진단 및 Android Studio 연결. 제거·복원 미구현.
- HIST-22–29: 공유 캐시와 프로젝트 생성물 측정. 공식 캐시·프로젝트 정리 실행 미구현.
- HIST-30: 앱 bundle ID 구분. CLI 링크 체인 진단은 미구현.
- HIST-31–34: 확장·앱 지원·컨테이너 크기 진단 및 보호. 프로필별 활성 버전 분석 미구현.
- HIST-35–36: 진단 전용. 전체 Caches/VM/folders 삭제 없음.
- HIST-37: Homebrew 캐시 측정. dry-run/cleanup 미구현.
- HIST-38: Unity 설치 목록. 프로젝트 버전 매칭 미구현.
- HIST-39: App Support 보호. AI 모델 전용 탐색 미구현.
- HIST-40: 휴지통 이동 전후 관측 가용 공간 기록. 휴지통 비우기 없음.
- HIST-41–42: 절대 경로 Process, 인자 배열, 사용자 환경 변경 없음. 셸 수정 도우미 미구현.
- HIST-43–44: 카테고리 차이 안내, 임의 폴더 읽기 전용 크기 탐색.
- HIST-45: 앱 실행 중 일일 알려진 캐시 분석. 무인 삭제 없음.

## 검증 범위

현재 32개 자동 테스트가 있으며 실제 FSEvents 수신도 검증합니다. 자동 테스트는 임시 fixture만 사용하며 실제 사용자 캐시를 삭제하지 않습니다. 분류, 숨김 프로젝트, 순수 Dart 오탐 방지, RN/Flutter 네이티브 묶기, 제외 경로, 링크·hardlink, 취소, SQLite, 마스킹, DerivedData 정책, Keep Warm, 변경·링크 바꿔치기, 보호 파일 및 내용 변경 지문을 검사합니다.

실제 디스크 전체 크롤·TCC 거부·오프라인 외장·APFS clone·실제 캐시 정리는 환경 의존 통합 QA가 남아 있습니다. 전체 v1.2 수용 기준 통과를 주장하지 않습니다.

## 증분 탐색 수용 범위

- DISC-08: FSEvents로 새로운 숨김 프로젝트 생성 감지 및 부분 재검사 지원.
- 프로젝트 제거·이동·식별 파일 변경은 범위별 병합하며, 접근 거부·취소는 기존 발견 결과를 지우지 않음.
- Quick Scan 이후 프로젝트 목록과 검사 루트 유지.
- SYS-22: 병합 인덱스 저장·재시작 로드. 재시작 공백은 전체 재검사 필요로 표시; 자동 이벤트 이력 재생은 아직 미지원.
- UserDropped/KernelDropped/RootChanged/Unmount/ID wrap 및 큰 이벤트 묶음은 전체 재검사로 복구하도록 안내.
- 감시는 전체 스캔 전에 시작하며 검사 중 이벤트를 대기열에 모아 기준 스캔 완료 후 재검사.
