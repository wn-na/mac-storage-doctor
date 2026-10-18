#!/bin/bash
set -euo pipefail
PACKAGE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
CHECK=$(mktemp -d "${TMPDIR:-/tmp}/storage-doctor-pkg.XXXXXX")
trap 'rm -rf "$CHECK"' EXIT
pkgutil --expand-full "$PACKAGE" "$CHECK/expanded"
export CHECK
python3 - <<'PY'
import os, pathlib, plistlib, xml.etree.ElementTree as ET
root = pathlib.Path(os.environ['CHECK'])/'expanded'
apps = list(root.glob('**/Payload/Applications/Mac Storage Doctor.app'))
assert len(apps) == 1, f'Expected exactly one application: {apps}'
app = apps[0]
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'dev.macstoragedoctor.app'
assert info['LSMinimumSystemVersion'] == '14.0'
assert info['LSUIElement'] is True
packages = list(root.glob('**/PackageInfo'))
assert len(packages) == 1
package = ET.parse(packages[0]).getroot()
assert package.attrib['identifier'] == 'dev.macstoragedoctor.pkg'
assert package.attrib['version'] == info['CFBundleShortVersionString']
assert package.attrib['install-location'] == '/'
assert not list(root.glob('**/Scripts')), 'No installer scripts are allowed'
assert package.attrib.get('relocatable') == 'false' and not package.findall('relocate/bundle'), 'The app must install to /Applications, not relocate to a development bundle'
distribution = ET.parse(root/'Distribution').getroot()
assert distribution.find('domains').attrib['enable_localSystem'] == 'true'
print(f'Validated payload, install path, version {package.attrib["version"]}, and absence of install scripts.')
(root/'app-path.txt').write_text(str(app))
PY
APP=$(cat "$CHECK/expanded/app-path.txt")
codesign --verify --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/MacStorageDoctor"
