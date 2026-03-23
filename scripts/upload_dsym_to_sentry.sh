#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="${APP_NAME:-Liney}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
DSYM_PATH="${DSYM_PATH:-$OUTPUT_DIR/DerivedData/Build/Products/Release/$APP_NAME.app.dSYM}"
SENTRY_CLI="${SENTRY_CLI:-sentry-cli}"
SENTRY_ORG="${SENTRY_ORG:-xnu}"
SENTRY_PROJECT="${SENTRY_PROJECT:-liney}"
SENTRY_INCLUDE_SOURCES="${SENTRY_INCLUDE_SOURCES:-0}"

usage() {
  cat <<EOF
Usage:
  scripts/upload_dsym_to_sentry.sh [--dsym <path>] [--app-name <name>] [--output-dir <path>]

Required environment:
  None when sentry-cli is already authenticated.

Optional environment:
  SENTRY_AUTH_TOKEN      Auth token for sentry-cli.
  SENTRY_ORG             Sentry organization slug. Default: xnu.
  SENTRY_PROJECT         Sentry project slug. Default: liney.
  SENTRY_URL             Self-hosted Sentry base URL.
  SENTRY_CLI             sentry-cli binary path. Default: sentry-cli.
  SENTRY_INCLUDE_SOURCES Upload source bundles together with the dSYM when set to 1.
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
    --dsym)
      require_value "$1" "${2:-}"
      DSYM_PATH="$2"
      shift 2
      ;;
    --app-name)
      require_value "$1" "${2:-}"
      APP_NAME="$2"
      shift 2
      ;;
    --output-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
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

if [[ -z "${SENTRY_ORG:-}" ]]; then
  echo "SENTRY_ORG is required." >&2
  exit 1
fi

if [[ -z "${SENTRY_PROJECT:-}" ]]; then
  echo "SENTRY_PROJECT is required." >&2
  exit 1
fi

if ! command -v "$SENTRY_CLI" >/dev/null 2>&1; then
  echo "Missing required command: $SENTRY_CLI" >&2
  exit 1
fi

if [[ ! -d "$DSYM_PATH" ]]; then
  echo "Missing dSYM bundle: $DSYM_PATH" >&2
  exit 1
fi

if ! "$SENTRY_CLI" info >/dev/null 2>&1; then
  echo "sentry-cli is not authenticated. Run: sentry-cli login" >&2
  echo "Or set SENTRY_AUTH_TOKEN for the release environment." >&2
  exit 1
fi

if command -v dwarfdump >/dev/null 2>&1; then
  echo "dSYM UUIDs:"
  dwarfdump --uuid "$DSYM_PATH"
fi

UPLOAD_ARGS=(
  debug-files
  upload
  --org "$SENTRY_ORG"
  --project "$SENTRY_PROJECT"
)

if [[ "$SENTRY_INCLUDE_SOURCES" == "1" ]]; then
  UPLOAD_ARGS+=(--include-sources)
fi

echo "Uploading dSYM to Sentry: $DSYM_PATH"
echo "Sentry target: $SENTRY_ORG/$SENTRY_PROJECT"
"$SENTRY_CLI" "${UPLOAD_ARGS[@]}" "$DSYM_PATH"
