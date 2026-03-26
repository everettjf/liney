#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_FILE="${PROJECT_FILE:-$ROOT_DIR/Liney.xcodeproj/project.pbxproj}"
PART="${1:-}"
VALUE="${2:-}"
NO_BUILD_BUMP="${NO_BUILD_BUMP:-0}"
BUILD_NUMBER_OVERRIDE="${BUILD_NUMBER_OVERRIDE:-}"

usage() {
  cat <<EOF
Usage:
  scripts/bump_version.sh <major|minor|patch>
  scripts/bump_version.sh set <version>

Environment:
  NO_BUILD_BUMP=1           Keep CURRENT_PROJECT_VERSION unchanged.
  BUILD_NUMBER_OVERRIDE=N   Explicitly set CURRENT_PROJECT_VERSION.
EOF
}

if [[ -z "$PART" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Missing Xcode project file: $PROJECT_FILE" >&2
  exit 1
fi

read_setting() {
  local key="$1"
  awk -F ' = ' -v key="$key" '$1 ~ key { gsub(/;/, "", $2); print $2; exit }' "$PROJECT_FILE"
}

validate_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
}

version_contains_four() {
  local version="$1"
  [[ "${version//./}" == *4* ]]
}

number_contains_four() {
  local value="$1"
  [[ "$value" == *4* ]]
}

validate_version_digits() {
  local version="$1"
  ! version_contains_four "$version"
}

validate_build_number_digits() {
  local value="$1"
  ! number_contains_four "$value"
}

next_number_without_four() {
  local value="$1"

  while number_contains_four "$value"; do
    value=$((value + 1))
  done

  echo "$value"
}

next_major_without_four() {
  local major_value="$1"

  while version_contains_four "$major_value.0.0"; do
    major_value=$((major_value + 1))
  done

  echo "$major_value"
}

next_minor_without_four() {
  local major_value="$1"
  local minor_value="$2"

  while version_contains_four "$major_value.$minor_value.0"; do
    minor_value=$((minor_value + 1))
  done

  echo "$minor_value"
}

next_patch_without_four() {
  local major_value="$1"
  local minor_value="$2"
  local patch_value="$3"

  while version_contains_four "$major_value.$minor_value.$patch_value"; do
    patch_value=$((patch_value + 1))
  done

  echo "$patch_value"
}

CURRENT_VERSION="$(read_setting MARKETING_VERSION)"
CURRENT_BUILD_NUMBER="$(read_setting CURRENT_PROJECT_VERSION)"

if ! validate_semver "$CURRENT_VERSION"; then
  echo "Unsupported current MARKETING_VERSION: $CURRENT_VERSION" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<< "$CURRENT_VERSION"
patch="${patch:-0}"
case "$PART" in
  major)
    major=$((major + 1))
    major="$(next_major_without_four "$major")"
    minor=0
    patch=0
    NEW_VERSION="$major.$minor.$patch"
    ;;
  minor)
    minor=$((minor + 1))
    minor="$(next_minor_without_four "$major" "$minor")"
    patch=0
    NEW_VERSION="$major.$minor.$patch"
    ;;
  patch)
    patch=$((patch + 1))
    patch="$(next_patch_without_four "$major" "$minor" "$patch")"
    NEW_VERSION="$major.$minor.$patch"
    ;;
  set)
    if [[ -z "$VALUE" ]]; then
      echo "set requires an explicit version." >&2
      usage >&2
      exit 1
    fi
    NEW_VERSION="$VALUE"
    ;;
  *)
    echo "Unknown bump part: $PART" >&2
    usage >&2
    exit 1
    ;;
esac

if ! validate_semver "$NEW_VERSION"; then
  echo "Invalid semantic version: $NEW_VERSION" >&2
  exit 1
fi

if ! validate_version_digits "$NEW_VERSION"; then
  echo "Invalid semantic version: version cannot contain digit 4: $NEW_VERSION" >&2
  exit 1
fi

IFS='.' read -r new_major new_minor new_patch <<< "$NEW_VERSION"
new_patch="${new_patch:-0}"
NEW_VERSION="$new_major.$new_minor.$new_patch"

NEW_BUILD_NUMBER="$CURRENT_BUILD_NUMBER"
if [[ -n "$BUILD_NUMBER_OVERRIDE" ]]; then
  NEW_BUILD_NUMBER="$BUILD_NUMBER_OVERRIDE"
elif [[ "$NO_BUILD_BUMP" != "1" ]]; then
  if [[ ! "$CURRENT_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Unsupported CURRENT_PROJECT_VERSION: $CURRENT_BUILD_NUMBER" >&2
    exit 1
  fi
  NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
  NEW_BUILD_NUMBER="$(next_number_without_four "$NEW_BUILD_NUMBER")"
fi

if [[ ! "$NEW_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid build number: $NEW_BUILD_NUMBER" >&2
  exit 1
fi

if ! validate_build_number_digits "$NEW_BUILD_NUMBER"; then
  echo "Invalid build number: build number cannot contain digit 4: $NEW_BUILD_NUMBER" >&2
  exit 1
fi

CURRENT_VERSION_REGEX="${CURRENT_VERSION//./\\.}"
sed -i '' -E "s/(MARKETING_VERSION = )$CURRENT_VERSION_REGEX;/\\1$NEW_VERSION;/g" "$PROJECT_FILE"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )$CURRENT_BUILD_NUMBER;/\\1$NEW_BUILD_NUMBER;/g" "$PROJECT_FILE"

echo "MARKETING_VERSION: $CURRENT_VERSION -> $NEW_VERSION"
echo "CURRENT_PROJECT_VERSION: $CURRENT_BUILD_NUMBER -> $NEW_BUILD_NUMBER"
