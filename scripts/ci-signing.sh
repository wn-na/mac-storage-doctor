#!/bin/bash
# Used only on disposable GitHub-hosted release runners.
set -euo pipefail
for NAME in DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD APP_SIGN_IDENTITY PKG_SIGN_IDENTITY NOTARY_APPLE_ID NOTARY_TEAM_ID NOTARY_PASSWORD; do
    [[ -n "${!NAME:-}" ]] || { echo "Missing signing secret: $NAME" >&2; exit 1; }
done
KEYCHAIN="$RUNNER_TEMP/storage-doctor-signing.keychain-db"
CERTIFICATE="$RUNNER_TEMP/storage-doctor-signing.p12"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
trap 'rm -f "$CERTIFICATE"' EXIT
printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERTIFICATE" -k "$KEYCHAIN" -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productbuild
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN"
xcrun notarytool store-credentials storage-doctor-ci --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --keychain "$KEYCHAIN"
printf '%s\n' 'NOTARY_PROFILE=storage-doctor-ci' "NOTARY_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
