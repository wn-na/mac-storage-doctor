#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-$(cat VERSION)}"
export BUILD_ARCHS="${BUILD_ARCHS:-arm64 x86_64}"
if [[ -n "${NOTARY_PROFILE:-}" && ( -z "${APP_SIGN_IDENTITY:-}" || -z "${PKG_SIGN_IDENTITY:-}" ) ]]; then
    echo 'Notarization requires both Application and Installer signing identities.' >&2; exit 1
fi
./scripts/build-app.sh
STAGE=$(mktemp -d "$PWD/.build/pkg-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/payload/Applications"
ditto "dist/Mac Storage Doctor.app" "$STAGE/payload/Applications/Mac Storage Doctor.app"
pkgbuild --analyze --root "$STAGE/payload" "$STAGE/components.plist"
export STAGE
python3 - <<'PY'
import os, pathlib, plistlib
root = pathlib.Path(os.environ['STAGE'])
components = plistlib.loads((root/'components.plist').read_bytes())
for component in components:
    component['BundleIsRelocatable'] = False
    component['BundleOverwriteAction'] = 'upgrade'
    component['BundleIsVersionChecked'] = True
(root/'components.plist').write_bytes(plistlib.dumps(components))
(root/'requirements.plist').write_bytes(plistlib.dumps({'os': ['14.0'], 'arch': os.environ['BUILD_ARCHS'].split()}))
PY
pkgbuild --root "$STAGE/payload" --component-plist "$STAGE/components.plist" \
    --identifier dev.macstoragedoctor.pkg --version "$VERSION" --install-location / "$STAGE/component.pkg"
productbuild --synthesize --product "$STAGE/requirements.plist" --package "$STAGE/component.pkg" "$STAGE/Distribution.xml"
python3 - <<'PY'
import os, pathlib, xml.etree.ElementTree as ET
path = pathlib.Path(os.environ['STAGE'])/'Distribution.xml'
tree = ET.parse(path); root = tree.getroot()
ET.SubElement(root, 'title').text = 'Mac Storage Doctor'
ET.SubElement(root, 'domains', {'enable_anywhere': 'false', 'enable_currentUserHome': 'false', 'enable_localSystem': 'true'})
tree.write(path, encoding='utf-8', xml_declaration=True)
PY
FLAVOR=unsigned
SIGN_ARGS=()
if [[ -n "${PKG_SIGN_IDENTITY:-}" ]]; then
    FLAVOR=signed
    SIGN_ARGS=(--sign "$PKG_SIGN_IDENTITY" --timestamp)
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then FLAVOR=notarized; fi
ARCH_LABEL=$(echo "$BUILD_ARCHS" | tr ' ' '-')
[[ "$BUILD_ARCHS" == 'arm64 x86_64' ]] && ARCH_LABEL=universal
OUTPUT="$PWD/dist/MacStorageDoctor-${VERSION}-${ARCH_LABEL}-${FLAVOR}.pkg"
productbuild --distribution "$STAGE/Distribution.xml" --package-path "$STAGE" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$OUTPUT"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=()
    if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then NOTARY_ARGS=(--keychain "$NOTARY_KEYCHAIN"); fi
    xcrun notarytool submit "$OUTPUT" --keychain-profile "$NOTARY_PROFILE" ${NOTARY_ARGS[@]+"${NOTARY_ARGS[@]}"} --wait --timeout 30m
    xcrun stapler staple "$OUTPUT"
    xcrun stapler validate "$OUTPUT"
    spctl --assess --type install --verbose=2 "$OUTPUT"
fi
./scripts/verify-pkg.sh "$OUTPUT"
(cd dist && shasum -a 256 "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256")
echo "Package: $OUTPUT"
