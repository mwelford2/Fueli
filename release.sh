#!/bin/bash
set -e

REPO="mwelford2/Fueli"
APPS_JSON="$(dirname "$0")/apps.json"

# ── Args ──────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $(basename "$0") [\"release notes\"]"
  echo "  release notes  optional; defaults to 'Version <version>.'"
  echo "  version is read automatically from the built IPA's Info.plist"
  exit 1
}

[[ "$1" == "-h" || "$1" == "--help" ]] && usage
NOTES_ARG="$1"
TODAY=$(date +%Y-%m-%d)

# ── Validate ──────────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "error: gh CLI not found. Install with: brew install gh" && exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "error: jq not found. Install with: brew install jq" && exit 1
fi

# The user requires every release check to pass, including device acceptance.
# This local manifest is created only after testing the exact candidate IPA.
EVIDENCE="$(dirname "$0")/.fueli-release-evidence.json"
if [[ ! -f "$EVIDENCE" ]]; then
  echo "error: release held; missing .fueli-release-evidence.json. See Fueli/TESTING_RELEASE_PLAN.md."
  exit 1
fi

# ── Build IPA ─────────────────────────────────────────────────────────────────
echo "==> Using the exact tested candidate IPA (no repackaging)..."
IPA_PATH="$(dirname "$0")/Fueli.ipa"
if [[ ! -f "$IPA_PATH" ]]; then
  echo "error: package Fueli.ipa and test that candidate before publication" && exit 1
fi
IPA_NAME="$(basename "$IPA_PATH")"
IPA_SIZE=$(wc -c < "$IPA_PATH" | tr -d ' ')

# Read the actual version string baked into the IPA so apps.json always matches
UNZIP_DIR=$(mktemp -d)
unzip -q "$IPA_PATH" -d "$UNZIP_DIR"
APP_PATH=$(find "$UNZIP_DIR/Payload" -maxdepth 1 -name "*.app" | head -1)
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")
if [[ "$BUNDLE_ID" != "com.welford.fueli" ]]; then
  rm -rf "$UNZIP_DIR"
  echo "error: refusing to publish an IPA with bundle ID $BUNDLE_ID"
  exit 1
fi
BUNDLED_USDA_KEY=$(/usr/libexec/PlistBuddy -c "Print :USDA_API_KEY" "$APP_PATH/Info.plist" 2>/dev/null || true)
if [[ -n "$BUNDLED_USDA_KEY" ]]; then
  rm -rf "$UNZIP_DIR"
  echo "error: refusing to publish an IPA containing a bundled USDA key. Rebuild Release with USDA_API_KEY empty."
  exit 1
fi
unset BUNDLED_USDA_KEY
rm -rf "$UNZIP_DIR"
python3 "$(dirname "$0")/scripts/verify_release.py" --evidence "$EVIDENCE" --ipa "$IPA_PATH"
SOURCE_COMMIT=$(git -C "$(dirname "$0")" rev-parse HEAD)

if [[ -z "$VERSION" ]]; then
  echo "error: could not read CFBundleShortVersionString from $IPA_PATH" && exit 1
fi
TAG="v${VERSION}"
NOTES="${NOTES_ARG:-Version ${VERSION}.}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${IPA_NAME}"

echo "==> IPA: $IPA_PATH ($IPA_SIZE bytes, version $VERSION)"

if gh release view "$TAG" --repo "$REPO" &>/dev/null 2>&1; then
  echo "error: release $TAG already exists; choose a new version. Existing releases are never deleted automatically."
  exit 1
fi

# ── GitHub release ────────────────────────────────────────────────────────────
echo "==> Creating GitHub release $TAG..."
NOTES_FILE=$(mktemp)
trap 'rm -f "$NOTES_FILE"' EXIT
printf '%s\n' "$NOTES" > "$NOTES_FILE"
gh release create "$TAG" "$IPA_PATH" \
  --repo "$REPO" \
  --title "Fueli $TAG" \
  --target "$SOURCE_COMMIT" \
  --notes-file "$NOTES_FILE"

# ── Update apps.json ──────────────────────────────────────────────────────────
echo "==> Updating apps.json..."

NEW_VERSION_ENTRY=$(jq -n \
  --arg version "$VERSION" \
  --arg date "$TODAY" \
  --arg notes "$NOTES" \
  --arg url "$DOWNLOAD_URL" \
  --argjson size "$IPA_SIZE" \
  '{version: $version, date: $date, localizedDescription: $notes, downloadURL: $url, size: $size}')

jq \
  --arg version "$VERSION" \
  --arg date "$TODAY" \
  --arg notes "$NOTES" \
  --arg url "$DOWNLOAD_URL" \
  --argjson size "$IPA_SIZE" \
  --argjson newEntry "$NEW_VERSION_ENTRY" \
  '
  .apps[0].versions = (if .apps[0].bundleIdentifier == "com.welford.fueli" then .apps[0].versions else [] end) |
  .apps[0].bundleIdentifier = "com.welford.fueli" |
  .apps[0].iconURL |= gsub("/CalClone/"; "/Fueli/") |
  .apps[0].version = $version |
  .apps[0].versionDate = $date |
  .apps[0].versionDescription = $notes |
  .apps[0].downloadURL = $url |
  .apps[0].size = $size |
  .apps[0].versions = [$newEntry] + (.apps[0].versions | map(select(.version != $version)))
  ' "$APPS_JSON" > "${APPS_JSON}.tmp" && mv "${APPS_JSON}.tmp" "$APPS_JSON"

echo "==> apps.json updated."

# ── Commit & push ─────────────────────────────────────────────────────────────
echo "==> Committing and pushing apps.json..."
git -C "$(dirname "$0")" add apps.json
git -C "$(dirname "$0")" commit -m "Release ${TAG}"
git -C "$(dirname "$0")" push

echo ""
echo "Done! Release live at: https://github.com/${REPO}/releases/tag/${TAG}"
echo "AltStore source URL:   https://raw.githubusercontent.com/${REPO}/main/apps.json"
