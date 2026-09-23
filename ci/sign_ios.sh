#!/usr/bin/env bash
set -euo pipefail

: "${IOS_CERTIFICATE_P12_B64:?IOS_CERTIFICATE_P12_B64 manquant}"
: "${IOS_CERTIFICATE_PASSWORD:?IOS_CERTIFICATE_PASSWORD manquant}"
: "${IOS_PROVISIONING_PROFILE_B64:?IOS_PROVISIONING_PROFILE_B64 manquant}"
: "${IOS_KEYCHAIN_PASSWORD:?IOS_KEYCHAIN_PASSWORD manquant}"

EXPECTED_BUNDLE_ID="fr.ecolegestion.ecoleGestionProfMobile"
APP_PATH="build/ios/iphoneos/Runner.app"
DIST_DIR="dist"
WORK_DIR="${RUNNER_TEMP:-/tmp}/gestcours-ios-signing"
KEYCHAIN="$WORK_DIR/gestcours-signing.keychain-db"
P12="$WORK_DIR/gestcours-distribution.p12"
PROFILE="$WORK_DIR/gestcours.mobileprovision"
PROFILE_PLIST="$WORK_DIR/profile.plist"
ENTITLEMENTS="$WORK_DIR/entitlements.plist"
PAYLOAD_ROOT="$WORK_DIR/package"
IPA_PATH="$PWD/$DIST_DIR/GESTCOURS_PROF_IOS_V0_5_6_OFFICIEL.ipa"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$DIST_DIR" "$PAYLOAD_ROOT/Payload"

printf '%s' "$IOS_CERTIFICATE_P12_B64" | base64 --decode > "$P12"
printf '%s' "$IOS_PROVISIONING_PROFILE_B64" | base64 --decode > "$PROFILE"
chmod 600 "$P12" "$PROFILE"

security create-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$IOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" "$(security list-keychains -d user | tr -d '"')"

security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$PROFILE_PLIST")
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PROFILE_PLIST")
APP_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PROFILE_PLIST")
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PROFILE_PLIST" 2>/dev/null || true)

PROFILE_BUNDLE_ID="${APP_IDENTIFIER#*.}"
if [[ "$PROFILE_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Profil incompatible : $PROFILE_BUNDLE_ID != $EXPECTED_BUNDLE_ID" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$PROFILE_PLIST" > "$ENTITLEMENTS"

IDENTITY_HASH=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/[0-9A-F]{40}/ {print $2; exit}')
if [[ -z "$IDENTITY_HASH" ]]; then
  echo "Aucune identité de signature iOS valide trouvée." >&2
  exit 1
fi

cp "$PROFILE" "$APP_PATH/embedded.mobileprovision"

if [[ -d "$APP_PATH/Frameworks" ]]; then
  while IFS= read -r -d '' item; do
    codesign --force --sign "$IDENTITY_HASH" --keychain "$KEYCHAIN" --timestamp=none "$item"
  done < <(find "$APP_PATH/Frameworks" \( -type d -name '*.framework' -o -type f -name '*.dylib' \) -print0)
fi

if [[ -d "$APP_PATH/PlugIns" ]]; then
  while IFS= read -r -d '' appex; do
    codesign --force --sign "$IDENTITY_HASH" --keychain "$KEYCHAIN" --timestamp=none "$appex"
  done < <(find "$APP_PATH/PlugIns" -type d -name '*.appex' -print0)
fi

codesign --force --sign "$IDENTITY_HASH" --keychain "$KEYCHAIN" --timestamp=none \
  --entitlements "$ENTITLEMENTS" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf "$PAYLOAD_ROOT/Payload/Runner.app"
cp -R "$APP_PATH" "$PAYLOAD_ROOT/Payload/Runner.app"
rm -f "$IPA_PATH"
(
  cd "$PAYLOAD_ROOT"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)

echo "Profil : $PROFILE_NAME"
echo "UUID : $PROFILE_UUID"
echo "Team ID : $TEAM_ID"
echo "Bundle ID : $PROFILE_BUNDLE_ID"
echo "Identité : $IDENTITY_HASH"
echo "IPA : $IPA_PATH"
