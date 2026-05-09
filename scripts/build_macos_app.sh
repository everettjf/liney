#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/sparkle_tools.sh"

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Liney.xcodeproj}"
SCHEME="${SCHEME:-Liney}"
APP_NAME="${APP_NAME:-Liney}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-Liney}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
RELEASE_ARCHS="${RELEASE_ARCHS:-arm64 x86_64}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$OUTPUT_DIR/DerivedData}"
STAGING_DIR="$OUTPUT_DIR/.dmg-staging"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
CREATE_DMG="${CREATE_DMG:-1}"
CLEAN_OUTPUT="${CLEAN_OUTPUT:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in xcodebuild xcrun /usr/bin/ditto /usr/bin/lipo /usr/bin/hdiutil /bin/mkdir; do
  require_cmd "$cmd"
done

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

if ! xcrun metal -v >/dev/null 2>&1; then
  cat >&2 <<EOF
Metal toolchain is unavailable for release builds.
Install it with:
  xcodebuild -downloadComponent MetalToolchain
EOF
  exit 1
fi

VENDORED_GHOSTTY_ARCHS="$(lipo -archs "$ROOT_DIR/Liney/Vendor/GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a" 2>/dev/null || true)"
IFS=' ' read -r -a ARCHS <<< "$RELEASE_ARCHS"
if [[ ${#ARCHS[@]} -eq 0 ]]; then
  echo "RELEASE_ARCHS must contain at least one architecture" >&2
  exit 1
fi

for arch in "${ARCHS[@]}"; do
  if [[ " $VENDORED_GHOSTTY_ARCHS " != *" $arch "* ]]; then
    echo "Vendored GhosttyKit does not include architecture: $arch" >&2
    echo "Available Ghostty architectures: $VENDORED_GHOSTTY_ARCHS" >&2
    exit 1
  fi
done

if [[ "$CLEAN_OUTPUT" == "1" ]]; then
  rm -rf "$APP_BUNDLE_PATH" "$DMG_PATH" "$STAGING_DIR" "$DERIVED_DATA_PATH"
fi

mkdir -p "$OUTPUT_DIR"

ARCHS_VALUE="${ARCHS[*]}"
echo "Building $APP_NAME ($ARCHS_VALUE) via Xcode..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ARCHS="$ARCHS_VALUE" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
  build

BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "Missing built app bundle: $BUILT_APP_PATH" >&2
  exit 1
fi

/usr/bin/ditto "$BUILT_APP_PATH" "$APP_BUNDLE_PATH"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$ROOT_DIR/Liney/Liney.entitlements}"
  /usr/bin/codesign --remove-signature "$APP_BUNDLE_PATH" >/dev/null 2>&1 || true
  sparkle_codesign_app "$APP_BUNDLE_PATH" "$SIGNING_IDENTITY" "$ENTITLEMENTS_PATH"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE_PATH"
fi

if [[ "$CREATE_DMG" == "1" ]]; then
  mkdir -p "$STAGING_DIR"
  /usr/bin/ditto "$APP_BUNDLE_PATH" "$STAGING_DIR/$APP_NAME.app"
  ln -s /Applications "$STAGING_DIR/Applications"
  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
fi

echo "App bundle: $APP_BUNDLE_PATH"
if [[ "$CREATE_DMG" == "1" ]]; then
  echo "DMG: $DMG_PATH"
fi
