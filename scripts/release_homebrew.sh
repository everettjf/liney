#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_FILE="${PROJECT_FILE:-$ROOT_DIR/Liney.xcodeproj/project.pbxproj}"
APP_NAME="${APP_NAME:-Liney}"
APP_SLUG="${APP_SLUG:-liney}"
APP_DESC="${APP_DESC:-Native macOS terminal workspace manager for git repositories, worktrees, and split panes.}"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Liney.xcodeproj}"
SCHEME="${SCHEME:-Liney}"
RELEASE_ARCHS="${RELEASE_ARCHS:-arm64}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APPCAST_FILE="${APPCAST_FILE:-$ROOT_DIR/appcast.xml}"
SIGN_SCRIPT="${SIGN_SCRIPT:-$ROOT_DIR/scripts/sign_macos.sh}"
ARCHIVE_DSYM_SCRIPT="${ARCHIVE_DSYM_SCRIPT:-$ROOT_DIR/scripts/archive_dsym.sh}"
UPLOAD_DSYM_SCRIPT="${UPLOAD_DSYM_SCRIPT:-$ROOT_DIR/scripts/upload_dsym_to_sentry.sh}"
TAP_REPO="${TAP_REPO:-everettjf/homebrew-tap}"
TAP_DIR_DEFAULT="$ROOT_DIR/tmp/homebrew-tap"
TAP_DIR="${TAP_DIR:-$TAP_DIR_DEFAULT}"
CASK_PATH="${CASK_PATH:-Casks/${APP_SLUG}.rb}"
APP_HOMEPAGE="${APP_HOMEPAGE:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
DEFAULT_NOTARYTOOL_PROFILE="${DEFAULT_NOTARYTOOL_PROFILE:-liney-notarytool}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-${APPLE_PASSWORD:-${APP_SPECIFIC_PASSWORD:-}}}"
LINEY_RELEASE_HOME="${LINEY_RELEASE_HOME:-$HOME/.liney_release}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$LINEY_RELEASE_HOME/sparkle_private_key}"
SPARKLE_MAX_VERSIONS="${SPARKLE_MAX_VERSIONS:-10}"
SPARKLE_CHANNEL="${SPARKLE_CHANNEL:-}"
SKIP_BUMP="${SKIP_BUMP:-0}"
BUMP_PART="${BUMP_PART:-patch}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_CASK_UPDATE="${SKIP_CASK_UPDATE:-0}"
SKIP_SENTRY_DSYM_UPLOAD="${SKIP_SENTRY_DSYM_UPLOAD:-0}"
FORCE_REBUILD="${FORCE_REBUILD:-1}"
RELEASE_NOTES_LIMIT="${RELEASE_NOTES_LIMIT:-50}"
RELEASE_NOTES_FILE=""
APPCAST_STAGING_DIR=""
CLONED_DEFAULT_TAP_DIR=0

source "$ROOT_DIR/scripts/sparkle_tools.sh"

usage() {
  cat <<EOF
Usage:
  scripts/release_homebrew.sh

Environment:
  SKIP_BUMP=1            Publish the current MARKETING_VERSION and CURRENT_PROJECT_VERSION unchanged.
  BUMP_PART=patch        Version bump part when SKIP_BUMP=0. patch also increments CURRENT_PROJECT_VERSION by 1.
  SKIP_NOTARIZE=1        Skip notarization in sign_macos.sh.
  SKIP_CASK_UPDATE=1     Skip updating the Homebrew tap repository.
  SKIP_SENTRY_DSYM_UPLOAD=1  Skip uploading the release dSYM to Sentry.
  TAP_REPO=owner/repo    Override the tap repo. Default: everettjf/homebrew-tap.
  LINEY_RELEASE_HOME=dir Release-only secret directory. Default: ~/.liney_release.
  DEFAULT_NOTARYTOOL_PROFILE=name  Auto-detected notarytool profile. Default: liney-notarytool.
  SPARKLE_PRIVATE_KEY_FILE=path  Private key used for Sparkle appcast signing.
EOF
}

read_setting() {
  local key="$1"
  awk -F ' = ' -v key="$key" '$1 ~ key { gsub(/;/, "", $2); print $2; exit }' "$PROJECT_FILE"
}

infer_release_repo() {
  local remote
  remote="$(git remote get-url origin 2>/dev/null || true)"
  if [[ "$remote" =~ ^git@github\.com:([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]%.git}"
    return
  fi
  if [[ "$remote" =~ ^https://github\.com/([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]%.git}"
    return
  fi
  if [[ "$remote" =~ ^ssh://git@github\.com/([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]%.git}"
    return
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

detect_notarytool_profile() {
  local profile="${1:-}"
  [[ -n "$profile" ]] || return 1
  xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1
}

ensure_clean_worktree() {
  if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "Working tree is not clean. Commit or stash changes before release." >&2
    exit 1
  fi
}

detect_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
    head -n 1
}

generate_release_notes() {
  local version="$1"
  local tag="$2"
  local previous_tag="$3"
  local dmg_name="$4"
  local release_notes_file
  local log_range
  local commit_count
  local compare_url=""
  local brew_install_ref

  release_notes_file="$(mktemp "${TMPDIR:-/tmp}/liney-release-notes.XXXXXX.md")"

  brew_install_ref="$(brew_install_target)"

  if [[ -n "$previous_tag" ]]; then
    log_range="$previous_tag..HEAD"
    compare_url="https://github.com/$RELEASE_REPO/compare/$previous_tag...$tag"
  else
    log_range="HEAD"
  fi

  commit_count="$(git rev-list --count $log_range)"
  {
    echo "## Release $version"
    echo
    echo "- DMG: \`$dmg_name\`"
    echo "- Homebrew: \`brew install --cask $brew_install_ref\`"
    if [[ -n "$previous_tag" ]]; then
      echo "- Previous release: \`$previous_tag\`"
    else
      echo "- Previous release: none"
    fi
    echo
    echo "## Included Commits"
    echo
    if [[ -n "$previous_tag" ]]; then
      echo "Showing the most recent ${RELEASE_NOTES_LIMIT} commits between \`$previous_tag\` and \`$tag\`."
    else
      echo "Showing the most recent ${RELEASE_NOTES_LIMIT} commits in repository history."
    fi
    echo
    git log \
      --max-count="$RELEASE_NOTES_LIMIT" \
      --pretty=format:'- `%h` %s' \
      $log_range
    if [[ "$commit_count" -gt "$RELEASE_NOTES_LIMIT" ]]; then
      echo
      echo
      echo "_Truncated to the most recent ${RELEASE_NOTES_LIMIT} commits out of ${commit_count}._"
    fi
    if [[ -n "$compare_url" ]]; then
      echo
      echo
      echo "Full diff: $compare_url"
    fi
  } > "$release_notes_file"

  echo "$release_notes_file"
}

brew_install_target() {
  if [[ "$TAP_REPO" =~ ^([^/]+)/homebrew-(.+)$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/$APP_SLUG"
    return
  fi

  echo "$APP_SLUG"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

for cmd in git gh shasum mktemp security; do
  require_cmd "$cmd"
done

if [[ -z "$NOTARYTOOL_PROFILE" ]] && detect_notarytool_profile "$DEFAULT_NOTARYTOOL_PROFILE"; then
  NOTARYTOOL_PROFILE="$DEFAULT_NOTARYTOOL_PROFILE"
fi

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Missing Xcode project file: $PROJECT_FILE" >&2
  exit 1
fi

if [[ ! -x "$SIGN_SCRIPT" ]]; then
  echo "Missing executable sign script: $SIGN_SCRIPT" >&2
  exit 1
fi

if [[ ! -x "$ARCHIVE_DSYM_SCRIPT" ]]; then
  echo "Missing executable dSYM archive script: $ARCHIVE_DSYM_SCRIPT" >&2
  exit 1
fi

if [[ "$SKIP_SENTRY_DSYM_UPLOAD" != "1" && ! -x "$UPLOAD_DSYM_SCRIPT" ]]; then
  echo "Missing executable dSYM upload script: $UPLOAD_DSYM_SCRIPT" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI not authenticated. Run: gh auth login" >&2
  exit 1
fi

RELEASE_REPO="${RELEASE_REPO:-$(infer_release_repo)}"
if [[ -z "$RELEASE_REPO" ]]; then
  echo "Unable to infer GitHub repo from origin. Set RELEASE_REPO=owner/repo." >&2
  exit 1
fi

if [[ -z "$APP_HOMEPAGE" ]]; then
  APP_HOMEPAGE="https://github.com/$RELEASE_REPO"
fi

cd "$ROOT_DIR"
ensure_clean_worktree

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(detect_signing_identity)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Unable to detect a Developer ID Application signing identity." >&2
  exit 1
fi

if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Missing Sparkle private key file: $SPARKLE_PRIVATE_KEY_FILE" >&2
  echo "Run scripts/setup_sparkle_keys.sh first, or set SPARKLE_PRIVATE_KEY_FILE / LINEY_RELEASE_HOME." >&2
  exit 1
fi

VERSION="$(read_setting MARKETING_VERSION)"
TAG="v$VERSION"
DIST_DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
DIST_ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.app.zip"
DIST_DSYM_PATH="$OUTPUT_DIR/dSYMs/$APP_NAME-$VERSION.app.dSYM"
DIST_DSYM_ZIP_PATH="$DIST_DSYM_PATH.zip"
RELEASE_DONE=0
DID_BUMP=0
PREVIOUS_TAG="$(git tag -l 'v*' --sort=-version:refname | head -n 1 || true)"

cleanup() {
  if [[ "$RELEASE_DONE" -eq 0 ]]; then
    git restore --source=HEAD --staged --worktree -- "$PROJECT_FILE" "$APPCAST_FILE" >/dev/null 2>&1 || true
  fi
  if [[ -n "$RELEASE_NOTES_FILE" && -f "$RELEASE_NOTES_FILE" ]]; then
    rm -f "$RELEASE_NOTES_FILE"
  fi
  if [[ -n "$APPCAST_STAGING_DIR" && -d "$APPCAST_STAGING_DIR" ]]; then
    rm -rf "$APPCAST_STAGING_DIR"
  fi
}
trap cleanup EXIT

if [[ "$SKIP_BUMP" != "1" ]]; then
  "$ROOT_DIR/scripts/bump_version.sh" "$BUMP_PART"
  DID_BUMP=1
  VERSION="$(read_setting MARKETING_VERSION)"
fi

TAG="v$VERSION"
DIST_DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
DIST_ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.app.zip"
DIST_DSYM_PATH="$OUTPUT_DIR/dSYMs/$APP_NAME-$VERSION.app.dSYM"
DIST_DSYM_ZIP_PATH="$DIST_DSYM_PATH.zip"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Tag already exists: $TAG" >&2
  exit 1
fi

SIGN_ARGS=(
  --identity "$SIGNING_IDENTITY"
  --version "$VERSION"
  --output-dir "$OUTPUT_DIR"
  --release-archs "$RELEASE_ARCHS"
)

if [[ "$FORCE_REBUILD" == "1" ]]; then
  SIGN_ARGS+=(--force-rebuild)
fi

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  SIGN_ARGS+=(--notarize)
fi

NOTARYTOOL_PROFILE="$NOTARYTOOL_PROFILE" \
APPLE_ID="$APPLE_ID" \
APPLE_TEAM_ID="$APPLE_TEAM_ID" \
APPLE_APP_SPECIFIC_PASSWORD="$APPLE_APP_SPECIFIC_PASSWORD" \
PROJECT_PATH="$PROJECT_PATH" \
SCHEME="$SCHEME" \
"$SIGN_SCRIPT" "${SIGN_ARGS[@]}"

if [[ ! -f "$DIST_DMG_PATH" ]]; then
  echo "Missing packaged DMG: $DIST_DMG_PATH" >&2
  exit 1
fi

APP_NAME="$APP_NAME" \
VERSION="$VERSION" \
OUTPUT_DIR="$OUTPUT_DIR" \
"$ARCHIVE_DSYM_SCRIPT" --version "$VERSION"

if [[ ! -d "$DIST_DSYM_PATH" || ! -f "$DIST_DSYM_ZIP_PATH" ]]; then
  echo "Missing archived dSYM artifacts: $DIST_DSYM_PATH / $DIST_DSYM_ZIP_PATH" >&2
  exit 1
fi

if [[ "$SKIP_SENTRY_DSYM_UPLOAD" != "1" ]]; then
  APP_NAME="$APP_NAME" \
  OUTPUT_DIR="$OUTPUT_DIR" \
  DSYM_PATH="$DIST_DSYM_PATH" \
  "$UPLOAD_DSYM_SCRIPT"
fi

RELEASE_NOTES_FILE="$(generate_release_notes "$VERSION" "$TAG" "$PREVIOUS_TAG" "$(basename "$DIST_DMG_PATH")")"
sparkle_create_app_zip "$OUTPUT_DIR/$APP_NAME.app" "$DIST_ZIP_PATH"

APPCAST_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/liney-appcast.XXXXXX")"
ZIP_BASENAME="$(basename "$DIST_ZIP_PATH" .zip)"
cp "$DIST_ZIP_PATH" "$APPCAST_STAGING_DIR/"
cp "$RELEASE_NOTES_FILE" "$APPCAST_STAGING_DIR/$ZIP_BASENAME.md"
if [[ -f "$APPCAST_FILE" ]]; then
  cp "$APPCAST_FILE" "$APPCAST_STAGING_DIR/appcast.xml"
fi

sparkle_generate_appcast \
  "$APPCAST_STAGING_DIR" \
  "$SPARKLE_PRIVATE_KEY_FILE" \
  "https://github.com/$RELEASE_REPO/releases/download/$TAG/" \
  "https://github.com/$RELEASE_REPO/releases/tag/$TAG" \
  "$APP_HOMEPAGE" \
  "$SPARKLE_MAX_VERSIONS" \
  "$SPARKLE_CHANNEL" \
  "$ROOT_DIR" \
  "$PROJECT_PATH" \
  "$SCHEME"

cp "$APPCAST_STAGING_DIR/appcast.xml" "$APPCAST_FILE"
rm -rf "$APPCAST_STAGING_DIR"

git add -- "$PROJECT_FILE" "$APPCAST_FILE"
if ! git diff --cached --quiet; then
  git commit -m "chore: release $VERSION"
  git push origin "$(git branch --show-current)"
fi

git tag "$TAG"
git push origin "$TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DIST_DMG_PATH" "$DIST_ZIP_PATH" "$DIST_DSYM_ZIP_PATH" "$APPCAST_FILE" --clobber
  gh release edit "$TAG" \
    --title "$APP_NAME $VERSION" \
    --notes-file "$RELEASE_NOTES_FILE"
else
  gh release create "$TAG" "$DIST_DMG_PATH" "$DIST_ZIP_PATH" "$DIST_DSYM_ZIP_PATH" "$APPCAST_FILE" \
    --title "$APP_NAME $VERSION" \
    --notes-file "$RELEASE_NOTES_FILE"
fi

if [[ "$SKIP_CASK_UPDATE" != "1" ]]; then
  SHA256="$(shasum -a 256 "$DIST_DMG_PATH" | awk '{print $1}')"

  if [[ "$TAP_DIR" == "$TAP_DIR_DEFAULT" ]]; then
    rm -rf "$TAP_DIR"
    mkdir -p "$(dirname "$TAP_DIR")"
    git clone "https://github.com/$TAP_REPO.git" "$TAP_DIR"
    CLONED_DEFAULT_TAP_DIR=1
  elif [[ ! -d "$TAP_DIR/.git" ]]; then
    mkdir -p "$(dirname "$TAP_DIR")"
    git clone "https://github.com/$TAP_REPO.git" "$TAP_DIR"
  fi

  cd "$TAP_DIR"
  git fetch origin
  if [[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]]; then
    git checkout main
  fi
  git pull --rebase origin main

  mkdir -p "$(dirname "$CASK_PATH")"
  if [[ ! -f "$CASK_PATH" ]]; then
    cat > "$CASK_PATH" <<EOF
cask "$APP_SLUG" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$RELEASE_REPO/releases/download/v#{version}/$APP_NAME-#{version}.dmg"
  name "$APP_NAME"
  desc "$APP_DESC"
  homepage "$APP_HOMEPAGE"

  app "$APP_NAME.app"
end
EOF
  else
    sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK_PATH"
    sed -i '' "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" "$CASK_PATH"
    sed -i '' "s|^  url \".*\"|  url \"https://github.com/$RELEASE_REPO/releases/download/v#{version}/$APP_NAME-#{version}.dmg\"|" "$CASK_PATH"
  fi

  git add "$CASK_PATH"
  if ! git diff --cached --quiet; then
    git commit -m "bump ${APP_SLUG} to $VERSION"
    if ! git push origin main; then
      git pull --rebase origin main
      git push origin main
    fi
  fi
fi

RELEASE_DONE=1
if [[ "$CLONED_DEFAULT_TAP_DIR" == "1" ]]; then
  rm -rf "$TAP_DIR"
fi
echo "Done. Released $TAG"
