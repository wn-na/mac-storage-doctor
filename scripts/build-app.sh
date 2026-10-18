#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
BUILD_ARCHS="${BUILD_ARCHS:-$(uname -m)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be major.minor.patch' >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'BUILD_NUMBER must be numeric' >&2; exit 1; }
mkdir -p .build dist
STAGE=$(mktemp -d "$PWD/.build/app-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Mac Storage Doctor.app"
mkdir -p "$APP/Contents/MacOS"
BINARIES=()
for ARCH in $BUILD_ARCHS; do
    [[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || { echo "Unsupported architecture: $ARCH" >&2; exit 1; }
    ARGS=(-c release --arch "$ARCH" --scratch-path "$PWD/.build/package-$ARCH" --disable-sandbox --cache-path "$PWD/.build/cache")
    swift build "${ARGS[@]}"
    BIN_DIR=$(swift build "${ARGS[@]}" --show-bin-path)
    BINARIES+=("$BIN_DIR/MacStorageDoctor")
done
[[ ${#BINARIES[@]} -gt 0 ]] || exit 1
if [[ ${#BINARIES[@]} == 1 ]]; then
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/MacStorageDoctor"
else
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/MacStorageDoctor"
fi
export VERSION BUILD_NUMBER APP
python3 - <<'PY'
import os, plistlib
info = dict(CFBundleExecutable='MacStorageDoctor', CFBundleIdentifier='dev.macstoragedoctor.app',
    CFBundleName='Mac Storage Doctor', CFBundleDisplayName='Mac Storage Doctor', CFBundlePackageType='APPL',
    CFBundleShortVersionString=os.environ['VERSION'], CFBundleVersion=os.environ['BUILD_NUMBER'],
    LSMinimumSystemVersion='14.0', LSUIElement=True, NSHighResolutionCapable=True, NSPrincipalClass='NSApplication',
    NSHumanReadableCopyright='Mac Storage Doctor')
with open(os.path.join(os.environ['APP'], 'Contents/Info.plist'), 'wb') as f: plistlib.dump(info, f)
PY
if [[ -n "${APP_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/MacStorageDoctor"
rm -rf "$PWD/dist/Mac Storage Doctor.app"
mv "$APP" "$PWD/dist/Mac Storage Doctor.app"
echo "Built: $PWD/dist/Mac Storage Doctor.app"
