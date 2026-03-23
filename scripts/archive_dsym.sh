#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="${APP_NAME:-Liney}"
VERSION="${VERSION:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
DSYM_SOURCE_PATH="${DSYM_SOURCE_PATH:-$OUTPUT_DIR/DerivedData/Build/Products/Release/$APP_NAME.app.dSYM}"
DSYM_ARCHIVE_DIR="${DSYM_ARCHIVE_DIR:-$OUTPUT_DIR/dSYMs}"

usage() {
  cat <<EOF
Usage:
  scripts/archive_dsym.sh --version <version> [--source <path>] [--output-dir <path>] [--archive-dir <path>]

Creates:
  <archive-dir>/<app-name>-<version>.app.dSYM
  <archive-dir>/<app-name>-<version>.app.dSYM.zip
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
    --version)
      require_value "$1" "${2:-}"
      VERSION="$2"
      shift 2
      ;;
    --source)
      require_value "$1" "${2:-}"
      DSYM_SOURCE_PATH="$2"
      shift 2
      ;;
    --output-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --archive-dir)
      require_value "$1" "${2:-}"
      DSYM_ARCHIVE_DIR="$2"
      shift 2
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

if [[ -z "$VERSION" ]]; then
  echo "VERSION is required." >&2
  exit 1
fi

for cmd in /usr/bin/ditto /bin/mkdir /bin/rm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

if [[ ! -d "$DSYM_SOURCE_PATH" ]]; then
  echo "Missing dSYM bundle: $DSYM_SOURCE_PATH" >&2
  exit 1
fi

mkdir -p "$DSYM_ARCHIVE_DIR"

DSYM_ARCHIVE_PATH="$DSYM_ARCHIVE_DIR/$APP_NAME-$VERSION.app.dSYM"
DSYM_ZIP_PATH="$DSYM_ARCHIVE_PATH.zip"

rm -rf "$DSYM_ARCHIVE_PATH" "$DSYM_ZIP_PATH"
/usr/bin/ditto "$DSYM_SOURCE_PATH" "$DSYM_ARCHIVE_PATH"
/usr/bin/ditto -c -k --keepParent "$DSYM_ARCHIVE_PATH" "$DSYM_ZIP_PATH"

echo "Archived dSYM: $DSYM_ARCHIVE_PATH"
echo "dSYM zip: $DSYM_ZIP_PATH"
