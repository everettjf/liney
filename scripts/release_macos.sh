#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/sparkle_tools.sh"

ARCHIVE_DSYM_SCRIPT="${ARCHIVE_DSYM_SCRIPT:-$ROOT_DIR/scripts/archive_dsym.sh}"
UPLOAD_DSYM_SCRIPT="${UPLOAD_DSYM_SCRIPT:-$ROOT_DIR/scripts/upload_dsym_to_sentry.sh}"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Liney.xcodeproj}"
SCHEME="${SCHEME:-Liney}"
APP_NAME="${APP_NAME:-Liney}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-Liney}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
RELEASE_ARCHS="${RELEASE_ARCHS:-arm64}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APPCAST_SOURCE_FILE="${APPCAST_SOURCE_FILE:-$ROOT_DIR/appcast.xml}"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-${APPLE_PASSWORD:-${APP_SPECIFIC_PASSWORD:-}}}"
LINEY_RELEASE_HOME="${LINEY_RELEASE_HOME:-$HOME/.liney_release}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$LINEY_RELEASE_HOME/sparkle_private_key}"
SPARKLE_MAX_VERSIONS="${SPARKLE_MAX_VERSIONS:-10}"
SPARKLE_CHANNEL="${SPARKLE_CHANNEL:-}"

SKIP_PUSH="${SKIP_PUSH:-0}"
SKIP_TAG="${SKIP_TAG:-0}"
SKIP_GH_RELEASE="${SKIP_GH_RELEASE:-0}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_SENTRY_DSYM_UPLOAD="${SKIP_SENTRY_DSYM_UPLOAD:-0}"
RELEASE_NOTES_FILE=""
APPCAST_STAGING_DIR=""

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "$RELEASE_NOTES_FILE" && -f "$RELEASE_NOTES_FILE" ]]; then
    rm -f "$RELEASE_NOTES_FILE"
  fi
  if [[ -n "$APPCAST_STAGING_DIR" && -d "$APPCAST_STAGING_DIR" ]]; then
    rm -rf "$APPCAST_STAGING_DIR"
  fi
}
trap cleanup EXIT

for cmd in git xcodebuild xcrun; do
  require_cmd "$cmd"
done

if [[ "$SKIP_SENTRY_DSYM_UPLOAD" != "1" && ! -x "$UPLOAD_DSYM_SCRIPT" ]]; then
  echo "Missing executable dSYM upload script: $UPLOAD_DSYM_SCRIPT" >&2
  exit 1
fi

if [[ ! -x "$ARCHIVE_DSYM_SCRIPT" ]]; then
  echo "Missing executable dSYM archive script: $ARCHIVE_DSYM_SCRIPT" >&2
  exit 1
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  require_cmd codesign
  require_cmd spctl
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Missing Xcode project: $PROJECT_PATH" >&2
  exit 1
fi

BUILD_SETTINGS_CACHE=""

load_build_settings() {
  if [[ -n "$BUILD_SETTINGS_CACHE" ]]; then
    return
  fi

  BUILD_SETTINGS_CACHE="$(
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination 'platform=macOS,arch=arm64' \
      -showBuildSettings
  )"
}

build_setting() {
  local key="$1"
  load_build_settings
  awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }' <<< "$BUILD_SETTINGS_CACHE"
}

VERSION="${VERSION:-$(build_setting MARKETING_VERSION)}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-$(build_setting PRODUCT_BUNDLE_IDENTIFIER)}"
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(build_setting CURRENT_PROJECT_VERSION)"
fi

if [[ -z "$VERSION" ]]; then
  echo "VERSION is empty" >&2
  exit 1
fi

if [[ -z "$BUNDLE_IDENTIFIER" ]]; then
  echo "BUNDLE_IDENTIFIER is empty" >&2
  exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  echo "BUILD_NUMBER is empty" >&2
  exit 1
fi

APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.app.zip"
DSYM_PATH="$OUTPUT_DIR/dSYMs/$APP_NAME-$VERSION.app.dSYM"
DSYM_ZIP_PATH="$DSYM_PATH.zip"
APPCAST_OUTPUT_PATH="$OUTPUT_DIR/appcast.xml"
TAG="${TAG:-v$VERSION}"

if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Missing Sparkle private key file: $SPARKLE_PRIVATE_KEY_FILE" >&2
  echo "Run scripts/setup_sparkle_keys.sh first, or set SPARKLE_PRIVATE_KEY_FILE / LINEY_RELEASE_HOME." >&2
  exit 1
fi

if [[ "$SKIP_GH_RELEASE" != "1" ]]; then
  require_cmd gh
  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
    exit 1
  fi
fi

if [[ -n "$(git status --short)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before release." >&2
  exit 1
fi

if [[ "$SKIP_PUSH" != "1" ]]; then
  git push origin "$(git branch --show-current)"
fi

APP_NAME="$APP_NAME" \
EXECUTABLE_NAME="$EXECUTABLE_NAME" \
BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
RELEASE_ARCHS="$RELEASE_ARCHS" \
OUTPUT_DIR="$OUTPUT_DIR" \
PROJECT_PATH="$PROJECT_PATH" \
SCHEME="$SCHEME" \
SIGNING_IDENTITY="$SIGNING_IDENTITY" \
"$ROOT_DIR/scripts/build_macos_app.sh"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  spctl --assess --type execute "$APP_BUNDLE_PATH"
fi

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  elif [[ -n "$APPLE_ID" && -n "$APPLE_TEAM_ID" && -n "$APPLE_APP_SPECIFIC_PASSWORD" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait
  else
    cat >&2 <<EOF
Notarization credentials missing.
Set one of:
  NOTARYTOOL_PROFILE=<keychain-profile>
  APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD
Or set:
  SKIP_NOTARIZE=1
EOF
    exit 1
  fi

  xcrun stapler staple "$APP_BUNDLE_PATH"
  xcrun stapler staple "$DMG_PATH"
fi

APP_NAME="$APP_NAME" \
VERSION="$VERSION" \
OUTPUT_DIR="$OUTPUT_DIR" \
"$ARCHIVE_DSYM_SCRIPT" --version "$VERSION"

if [[ ! -d "$DSYM_PATH" || ! -f "$DSYM_ZIP_PATH" ]]; then
  echo "Missing archived dSYM artifacts: $DSYM_PATH / $DSYM_ZIP_PATH" >&2
  exit 1
fi

if [[ "$SKIP_SENTRY_DSYM_UPLOAD" != "1" ]]; then
  APP_NAME="$APP_NAME" \
  OUTPUT_DIR="$OUTPUT_DIR" \
  DSYM_PATH="$DSYM_PATH" \
  "$UPLOAD_DSYM_SCRIPT"
fi

if [[ "$SKIP_TAG" != "1" ]]; then
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Tag already exists: $TAG" >&2
    exit 1
  fi
  git tag "$TAG"
  if [[ "$SKIP_PUSH" != "1" ]]; then
    git push origin "$TAG"
  fi
fi

RELEASE_NOTES_FILE="$(mktemp "${TMPDIR:-/tmp}/liney-release-notes.XXXXXX.md")"
cat > "$RELEASE_NOTES_FILE" <<EOF
## Liney $VERSION

- GitHub release: https://github.com/everettjf/liney/releases/tag/$TAG
EOF

APPCAST_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/liney-appcast.XXXXXX")"
ZIP_BASENAME="$(basename "$ZIP_PATH" .zip)"

sparkle_create_app_zip "$APP_BUNDLE_PATH" "$ZIP_PATH"
cp "$ZIP_PATH" "$APPCAST_STAGING_DIR/"
cp "$RELEASE_NOTES_FILE" "$APPCAST_STAGING_DIR/$ZIP_BASENAME.md"
if [[ -f "$APPCAST_SOURCE_FILE" ]]; then
  cp "$APPCAST_SOURCE_FILE" "$APPCAST_STAGING_DIR/appcast.xml"
fi

sparkle_generate_appcast \
  "$APPCAST_STAGING_DIR" \
  "$SPARKLE_PRIVATE_KEY_FILE" \
  "https://github.com/everettjf/liney/releases/download/$TAG/" \
  "https://github.com/everettjf/liney/releases/tag/$TAG" \
  "https://github.com/everettjf/liney" \
  "$SPARKLE_MAX_VERSIONS" \
  "$SPARKLE_CHANNEL" \
  "$ROOT_DIR" \
  "$PROJECT_PATH" \
  "$SCHEME"

cp "$APPCAST_STAGING_DIR/appcast.xml" "$APPCAST_OUTPUT_PATH"
rm -rf "$APPCAST_STAGING_DIR"
APPCAST_STAGING_DIR=""
rm -f "$RELEASE_NOTES_FILE"
RELEASE_NOTES_FILE=""

if [[ "$SKIP_GH_RELEASE" != "1" ]]; then
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG_PATH" "$ZIP_PATH" "$DSYM_ZIP_PATH" "$APPCAST_OUTPUT_PATH" --clobber
    gh release edit "$TAG" \
      --title "$APP_NAME $VERSION" \
      --notes "Release $VERSION"
  else
    gh release create "$TAG" "$DMG_PATH" "$ZIP_PATH" "$DSYM_ZIP_PATH" "$APPCAST_OUTPUT_PATH" \
      --title "$APP_NAME $VERSION" \
      --notes "Release $VERSION"
  fi
fi

echo "Release ready:"
echo "  App bundle: $APP_BUNDLE_PATH"
echo "  DMG: $DMG_PATH"
echo "  ZIP: $ZIP_PATH"
echo "  Appcast: $APPCAST_OUTPUT_PATH"
