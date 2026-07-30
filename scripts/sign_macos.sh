#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Liney.xcodeproj}"
SCHEME="${SCHEME:-Liney}"
APP_NAME="${APP_NAME:-Liney}"
VERSION="${VERSION:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-}"
DMG_PATH="${DMG_PATH:-}"
RELEASE_ARCHS="${RELEASE_ARCHS:-arm64 x86_64}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$ROOT_DIR/Liney/Liney.entitlements}"
BUILD_IF_MISSING="${BUILD_IF_MISSING:-1}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
NOTARIZE="${NOTARIZE:-0}"
APPLE_ID="${APPLE_ID:-}"
APPLE_SPECIFIC_PASSWORD="${APPLE_SPECIFIC_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
STAGING_DIR="$OUTPUT_DIR/.signed-dmg-staging"

source "$ROOT_DIR/scripts/sparkle_tools.sh"

detect_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
    head -n 1
}

usage() {
  cat <<EOF
Usage:
  scripts/sign_macos.sh --identity "<Developer ID>" [--version <version>] [--notarize]

Options:
  --identity <name>      Signing identity used by codesign.
  --version <version>    Override MARKETING_VERSION for the packaged DMG.
  --output-dir <path>    Release artifact directory. Default: dist.
  --app <path>           Existing .app bundle to sign.
  --dmg <path>           Output DMG path. Default: dist/Liney-<version>.dmg.
  --release-archs <v>    Passed through to build_macos_app.sh when rebuilding.
  --no-build             Fail instead of building when the app bundle is missing.
  --force-rebuild        Rebuild the unsigned app before signing.
  --notarize             Submit the DMG for notarization and staple results.
                        Requires APPLE_ID, APPLE_SPECIFIC_PASSWORD, and APPLE_TEAM_ID.
  --help                 Show this help.
EOF
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "Missing value for $option" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      require_value "$1" "${2:-}"
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --version)
      require_value "$1" "${2:-}"
      VERSION="$2"
      shift 2
      ;;
    --output-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --app)
      require_value "$1" "${2:-}"
      APP_BUNDLE_PATH="$2"
      shift 2
      ;;
    --dmg)
      require_value "$1" "${2:-}"
      DMG_PATH="$2"
      shift 2
      ;;
    --release-archs)
      require_value "$1" "${2:-}"
      RELEASE_ARCHS="$2"
      shift 2
      ;;
    --no-build)
      BUILD_IF_MISSING=0
      shift
      ;;
    --force-rebuild)
      FORCE_REBUILD=1
      shift
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(detect_signing_identity)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Signing identity is required." >&2
  usage >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in codesign security xcodebuild xcrun /usr/bin/ditto /usr/bin/hdiutil /bin/mkdir /bin/rm; do
  require_cmd "$cmd"
done

read_build_setting() {
  local key="$1"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -showBuildSettings |
    awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
}

VERSION="${VERSION:-$(read_build_setting MARKETING_VERSION)}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-$OUTPUT_DIR/$APP_NAME.app}"
DMG_PATH="${DMG_PATH:-$OUTPUT_DIR/$APP_NAME-$VERSION.dmg}"

echo "Using signing identity: $SIGNING_IDENTITY"

if [[ "$FORCE_REBUILD" == "1" || ! -d "$APP_BUNDLE_PATH" ]]; then
  if [[ "$BUILD_IF_MISSING" != "1" ]]; then
    echo "Missing app bundle: $APP_BUNDLE_PATH" >&2
    exit 1
  fi

  PROJECT_PATH="$PROJECT_PATH" \
  SCHEME="$SCHEME" \
  VERSION="$VERSION" \
  RELEASE_ARCHS="$RELEASE_ARCHS" \
  OUTPUT_DIR="$OUTPUT_DIR" \
  CREATE_DMG=0 \
  CLEAN_OUTPUT="$FORCE_REBUILD" \
  "$ROOT_DIR/scripts/build_macos_app.sh"
fi

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  echo "Missing app bundle: $APP_BUNDLE_PATH" >&2
  exit 1
fi

/usr/bin/codesign --remove-signature "$APP_BUNDLE_PATH" >/dev/null 2>&1 || true
sparkle_codesign_app "$APP_BUNDLE_PATH" "$SIGNING_IDENTITY" "$ENTITLEMENTS_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_PATH"
/usr/sbin/spctl --assess -vv --type execute "$APP_BUNDLE_PATH"

rm -rf "$DMG_PATH" "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
/usr/bin/ditto "$APP_BUNDLE_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$APPLE_ID" || -z "$APPLE_SPECIFIC_PASSWORD" || -z "$APPLE_TEAM_ID" ]]; then
    cat >&2 <<EOF
Notarization credentials missing.
Set APPLE_ID, APPLE_SPECIFIC_PASSWORD, and APPLE_TEAM_ID.
EOF
    exit 1
  fi

  NOTARY_AUTH_ARGS=(
    --apple-id "$APPLE_ID"
    --password "$APPLE_SPECIFIC_PASSWORD"
    --team-id "$APPLE_TEAM_ID"
  )

  echo "Submitting $DMG_PATH for notarization..."
  NOTARY_SUBMIT_LOG="$OUTPUT_DIR/notarytool-submit.log"
  : >"$NOTARY_SUBMIT_LOG"
  # `xcrun notarytool submit` occasionally crashes with SIGBUS *after* Apple
  # has already returned the submission id. Capture the exit code without
  # aborting, then fall back to the log: if an id was issued, the upload
  # actually succeeded and we should proceed to poll status.
  set +e
  xcrun notarytool submit "$DMG_PATH" "${NOTARY_AUTH_ARGS[@]}" 2>&1 | tee "$NOTARY_SUBMIT_LOG"
  NOTARY_SUBMIT_RC=${PIPESTATUS[0]}
  set -e
  SUBMIT_OUTPUT=$(<"$NOTARY_SUBMIT_LOG")
  SUBMISSION_ID=$(printf '%s\n' "$SUBMIT_OUTPUT" \
    | sed -n 's/^[[:space:]]*id:[[:space:]]*//p' \
    | head -n1)
  if [[ -z "$SUBMISSION_ID" ]]; then
    echo "notarytool submit failed (exit $NOTARY_SUBMIT_RC) and no submission id was parsed (see $NOTARY_SUBMIT_LOG)" >&2
    exit 1
  fi
  if [[ "$NOTARY_SUBMIT_RC" -ne 0 ]]; then
    echo "notarytool submit exited $NOTARY_SUBMIT_RC after receiving submission id $SUBMISSION_ID; continuing to poll status." >&2
  fi
  echo "Submission id: $SUBMISSION_ID"

  # Best-effort: poll briefly so we can staple if Apple is fast, but don't
  # block the release if notarization is still queued. An un-stapled DMG is
  # still notarized server-side — Gatekeeper fetches the ticket online on
  # first launch. Hard-fail only on an explicit reject (Invalid/Rejected).
  POLL_INTERVAL="${NOTARYTOOL_POLL_INTERVAL:-15}"
  POLL_TIMEOUT="${NOTARYTOOL_POLL_TIMEOUT:-120}"
  POLL_DEADLINE=$(( $(date +%s) + POLL_TIMEOUT ))
  NOTARIZATION_ACCEPTED=0
  while :; do
    if (( $(date +%s) > POLL_DEADLINE )); then
      echo "Notarization still pending after ${POLL_TIMEOUT}s; continuing without stapling (id: $SUBMISSION_ID)." >&2
      echo "Check later with xcrun notarytool info using the same Apple environment credentials." >&2
      break
    fi
    if ! INFO_OUTPUT=$(xcrun notarytool info "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" 2>&1); then
      echo "notarytool info failed; retrying in ${POLL_INTERVAL}s..." >&2
      sleep "$POLL_INTERVAL"
      continue
    fi
    STATUS=$(printf '%s\n' "$INFO_OUTPUT" \
      | sed -n 's/^[[:space:]]*status:[[:space:]]*//p' \
      | head -n1)
    echo "Notarization status: ${STATUS:-unknown}"
    case "$STATUS" in
      Accepted)
        NOTARIZATION_ACCEPTED=1
        break
        ;;
      "In Progress"|"")
        sleep "$POLL_INTERVAL"
        ;;
      *)
        echo "Notarization ended with status: $STATUS" >&2
        xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" >&2 || true
        exit 1
        ;;
    esac
  done

  if [[ "$NOTARIZATION_ACCEPTED" == "1" ]]; then
    xcrun stapler staple "$APP_BUNDLE_PATH"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  else
    echo "Skipping stapler: notarization not yet Accepted. DMG will rely on online Gatekeeper check at first launch." >&2
  fi
fi

echo "Signed app bundle: $APP_BUNDLE_PATH"
echo "Signed DMG: $DMG_PATH"
