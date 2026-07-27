#!/bin/bash
set -e

REPO="mwelford2/Fueli"
APPS_JSON="$(dirname "$0")/apps.json"

# ── Args ──────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $(basename "$0") <version> [\"release notes\"]"
  echo "  version      e.g. 1.2.0"
  echo "  release notes  optional; defaults to 'Version <version>.'"
  exit 1
}

[[ -z "$1" ]] && usage
VERSION="$1"
TAG="v${VERSION}"
NOTES="${2:-Version ${VERSION}.}"
TODAY=$(date +%Y-%m-%d)

# ── Validate ──────────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "error: gh CLI not found. Install with: brew install gh" && exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "error: jq not found. Install with: brew install jq" && exit 1
fi
if gh release view "$TAG" --repo "$REPO" &>/dev/null 2>&1; then
  echo "error: release $TAG already exists on GitHub." && exit 1
fi

# ── Build IPA ─────────────────────────────────────────────────────────────────
echo "==> Packaging IPA from most recent Xcode archive..."
make-ipa.sh

IPA_PATH="$(ls -t "$(dirname "$0")"/*.ipa 2>/dev/null | head -1)"
if [[ -z "$IPA_PATH" ]]; then
  echo "error: no .ipa found in project directory after make-ipa.sh" && exit 1
fi
IPA_NAME="$(basename "$IPA_PATH")"
IPA_SIZE=$(wc -c < "$IPA_PATH" | tr -d ' ')
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${IPA_NAME}"

# Read the actual version string baked into the IPA so apps.json always matches
UNZIP_DIR=$(mktemp -d)
unzip -q "$IPA_PATH" -d "$UNZIP_DIR"
APP_PATH=$(find "$UNZIP_DIR/Payload" -maxdepth 1 -name "*.app" | head -1)
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Info.plist")
rm -rf "$UNZIP_DIR"

if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
  echo "warning: IPA CFBundleShortVersionString is '$BUNDLE_VERSION', not '$VERSION'."
  echo "         Using '$BUNDLE_VERSION' in apps.json to match the binary."
  VERSION="$BUNDLE_VERSION"
fi

echo "==> IPA: $IPA_PATH ($IPA_SIZE bytes, version $VERSION)"

# ── GitHub release ────────────────────────────────────────────────────────────
echo "==> Creating GitHub release $TAG..."
gh release create "$TAG" "$IPA_PATH" \
  --repo "$REPO" \
  --title "Fueli $TAG" \
  --notes "$NOTES"

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
  .apps[0].version = $version |
  .apps[0].versionDate = $date |
  .apps[0].versionDescription = $notes |
  .apps[0].downloadURL = $url |
  .apps[0].size = $size |
  .apps[0].versions = [$newEntry] + .apps[0].versions
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
