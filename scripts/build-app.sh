#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
APP="$PWD/dist/Mac Storage Doctor.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacStorageDoctor "$APP/Contents/MacOS/MacStorageDoctor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacStorageDoctor</string>
<key>CFBundleIdentifier</key><string>dev.macstoragedoctor.app</string>
<key>CFBundleName</key><string>Mac Storage Doctor</string>
<key>CFBundleDisplayName</key><string>Mac Storage Doctor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Mac Storage Doctor</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "Built: $APP"
