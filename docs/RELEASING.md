# GitHub PKG 배포

저장소: https://github.com/wn-na/mac-storage-doctor

## 사용자 설치

GitHub **Releases**에서 `.pkg`와 같은 이름의 `.sha256` 파일을 받습니다. macOS 14 이상과 Apple Silicon / Intel을 지원하는 Universal 앱을 `/Applications/Mac Storage Doctor.app`에 설치합니다. 설치 스크립트가 없으며 사용자의 파일·셸 설정·캐시를 변경하지 않습니다. 설치에는 Applications 쓰기 권한이 필요합니다.

앱 실행 후 메뉴바에서 여유 공간, 사용 공간 또는 사용률을 선택할 수 있습니다. 상세 창을 닫아도 계속 실행됩니다. Settings의 **로그인 시 자동 실행**은 Applications에 설치한 앱에서 활성화할 수 있으며 macOS 승인이 필요하면 로그인 항목 설정을 안내합니다. PKG가 자동 실행 권한이나 Full Disk Access를 부여하지 않습니다.

```sh
shasum -a 256 -c MacStorageDoctor-0.3.0-universal-unsigned.pkg.sha256
```

`unsigned`는 앱에 ad-hoc 서명만 있고 설치 패키지에는 Developer ID 서명·공증이 없다는 뜻입니다. Gatekeeper가 설치를 차단할 수 있습니다. 개발용 프리릴리스이며 일반 사용자에게 권장하는 정식 배포물은 아닙니다. `notarized` 패키지는 Developer ID 서명 및 Apple 공증을 완료한 산출물입니다.

## 릴리스 생성

1. `VERSION`을 `major.minor.patch` 형식으로 변경합니다.
2. 코드·문서·버전을 커밋하고 `main`에 푸시합니다.
3. CI의 테스트 성공을 확인합니다.
4. 같은 버전 태그를 만들어 푸시합니다.

```sh
git tag -a v0.3.0 -m 'Mac Storage Doctor 0.3.0'
git push origin v0.3.0
```

`Release PKG` 워크플로가 테스트 → arm64/x86_64 빌드 → Universal 앱 → PKG 구조 검증 → SHA-256 생성 → GitHub Release 게시를 실행합니다. 미서명 또는 0.x 버전은 prerelease로 게시됩니다. 일반 `main` 푸시와 PR은 두 아키텍처에서 테스트하고 앱을 빌드합니다.

Actions의 수동 `Run workflow`는 기본적으로 Artifact만 생성합니다. `publish`를 켜면 현재 커밋과 일치하는 `vVERSION` 태그가 있어야 게시합니다. 이미 게시된 같은 이름의 파일을 덮어쓰지 않으며 수정 배포는 버전을 올립니다.

## 로컬 PKG

```sh
./scripts/build-pkg.sh
./scripts/verify-pkg.sh dist/MacStorageDoctor-0.3.0-universal-unsigned.pkg
```

`dist/`는 Git에 넣지 않습니다. Git에는 소스·워크플로·버전만 보관하고 설치 파일은 Releases 또는 Actions Artifacts로 제공합니다. 패키지는 기존 앱의 bundle identifier를 유지하고 개발 폴더의 앱으로 설치 위치가 옮겨가지 않도록 relocation을 비활성화합니다.

## 정식 서명과 공증

Apple Developer 계정의 **Developer ID Application** 및 **Developer ID Installer** 인증서가 필요합니다. 인증서의 개인 키, 비밀번호, Apple 앱 암호를 저장소나 채팅에 넣지 마세요. GitHub Settings → Secrets and variables → Actions에서 아래 항목을 설정합니다.

| Secret | 값 |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | 두 인증서와 개인 키를 포함한 P12 파일의 base64 |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | P12 암호 |
| `APP_SIGN_IDENTITY` | Developer ID Application 인증서 이름 |
| `PKG_SIGN_IDENTITY` | Developer ID Installer 인증서 이름 |
| `NOTARY_APPLE_ID` | Apple ID |
| `NOTARY_TEAM_ID` | Developer Team ID |
| `NOTARY_PASSWORD` | 공증용 앱 암호 |

Repository variable `APPLE_SIGNING_ENABLED=true`를 설정하면 다음 릴리스부터 서명·공증을 필수로 실행합니다. 설정이 불완전하거나 공증이 실패하면 배포를 중단하며 미서명 파일로 대체하지 않습니다. 임시 keychain은 해당 GitHub-hosted runner 안에서만 생성하고 종료 시 삭제합니다.

로컬에서는 `APP_SIGN_IDENTITY`, `PKG_SIGN_IDENTITY`, `NOTARY_PROFILE`을 지정해 동일 스크립트를 사용합니다. `NOTARY_PROFILE`은 `notarytool store-credentials`로 미리 저장한 프로필입니다. 별도 keychain을 쓰면 `NOTARY_KEYCHAIN`도 지정할 수 있습니다.

인증서가 없는 현재 개발 환경에서는 서명·공증 단계가 실제 검증되지 않았습니다. 첫 서명 릴리스는 별도로 설치·공증 QA를 해야 합니다. 설치 패키지의 내용과 서명은 자동 검증하지만 실제 `/Applications` 설치/업그레이드는 사용자 시스템을 변경하므로 자동 테스트에서 수행하지 않습니다.

참고: [Apple 배포 패키징](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [Developer ID](https://developer.apple.com/developer-id/), [공증](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
