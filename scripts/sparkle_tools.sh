#!/usr/bin/env bash

sparkle_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/.." && pwd
}

sparkle_require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    return 1
  fi
}

sparkle_source_packages_dir() {
  local root_dir="${1:-$(sparkle_repo_root)}"
  echo "${SPARKLE_SOURCE_PACKAGES_DIR:-$root_dir/.build/SourcePackages}"
}

sparkle_checkout_dir() {
  local root_dir="${1:-$(sparkle_repo_root)}"
  local project_path="${2:-$root_dir/Liney.xcodeproj}"
  local scheme="${3:-Liney}"
  local source_packages_dir
  source_packages_dir="$(sparkle_source_packages_dir "$root_dir")"

  sparkle_require_cmd xcodebuild || return 1
  mkdir -p "$source_packages_dir"
  xcodebuild \
    -project "$project_path" \
    -scheme "$scheme" \
    -resolvePackageDependencies \
    -clonedSourcePackagesDirPath "$source_packages_dir" >/dev/null

  local checkout_dir="$source_packages_dir/checkouts/Sparkle"
  if [[ ! -d "$checkout_dir" ]]; then
    echo "Unable to locate Sparkle checkout in $source_packages_dir" >&2
    return 1
  fi

  echo "$checkout_dir"
}

sparkle_tool_path() {
  local tool_name="$1"
  local root_dir="${2:-$(sparkle_repo_root)}"
  local project_path="${3:-$root_dir/Liney.xcodeproj}"
  local scheme="${4:-Liney}"

  sparkle_require_cmd xcodebuild || return 1
  local checkout_dir
  checkout_dir="$(sparkle_checkout_dir "$root_dir" "$project_path" "$scheme")" || return 1

  local derived_data_path="${SPARKLE_DERIVED_DATA_DIR:-$root_dir/.build/SparkleDerivedData}/$tool_name"
  xcodebuild \
    -project "$checkout_dir/Sparkle.xcodeproj" \
    -scheme "$tool_name" \
    -configuration Release \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null

  local tool_path="$derived_data_path/Build/Products/Release/$tool_name"
  if [[ ! -x "$tool_path" ]]; then
    echo "Missing Sparkle tool after build: $tool_path" >&2
    return 1
  fi

  echo "$tool_path"
}

sparkle_sign_embedded_bundle() {
  local app_path="$1"
  local signing_identity="$2"
  local framework_path="$app_path/Contents/Frameworks/Sparkle.framework"

  [[ -d "$framework_path" ]] || return 0
  sparkle_require_cmd codesign || return 1

  local version_dir
  version_dir="$(find "$framework_path/Versions" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "$version_dir" || ! -d "$version_dir" ]]; then
    echo "Unable to locate Sparkle framework version directory in $framework_path" >&2
    return 1
  fi

  local sign_runtime=(
    /usr/bin/codesign
    --force
    --sign "$signing_identity"
    --options runtime
    --timestamp
  )
  local sign_runtime_preserving=(
    /usr/bin/codesign
    --force
    --sign "$signing_identity"
    --options runtime
    --timestamp
    --preserve-metadata=entitlements,requirements,flags
  )

  [[ -d "$version_dir/XPCServices/Installer.xpc" ]] && "${sign_runtime[@]}" "$version_dir/XPCServices/Installer.xpc"
  [[ -d "$version_dir/XPCServices/Downloader.xpc" ]] && "${sign_runtime_preserving[@]}" "$version_dir/XPCServices/Downloader.xpc"
  [[ -d "$version_dir/Updater.app" ]] && "${sign_runtime[@]}" "$version_dir/Updater.app"
  [[ -x "$version_dir/Autoupdate" ]] && "${sign_runtime[@]}" "$version_dir/Autoupdate"
  [[ -x "$version_dir/Sparkle" ]] && "${sign_runtime[@]}" "$version_dir/Sparkle"
  "${sign_runtime[@]}" "$framework_path"
}

sparkle_sign_embedded_frameworks() {
  local app_path="$1"
  local signing_identity="$2"
  local frameworks_dir="$app_path/Contents/Frameworks"

  [[ -d "$frameworks_dir" ]] || return 0
  sparkle_require_cmd codesign || return 1

  local sign_runtime_preserving=(
    /usr/bin/codesign
    --force
    --sign "$signing_identity"
    --options runtime
    --timestamp
    --preserve-metadata=identifier,entitlements,requirements,flags
  )

  local framework_path
  while IFS= read -r -d '' framework_path; do
    "${sign_runtime_preserving[@]}" "$framework_path"
  done < <(find "$frameworks_dir" -mindepth 1 -maxdepth 1 -type d -name '*.framework' ! -name 'Sparkle.framework' -print0)
}

sparkle_codesign_app() {
  local app_path="$1"
  local signing_identity="$2"
  local entitlements_path="${3:-}"

  sparkle_sign_embedded_frameworks "$app_path" "$signing_identity" || return 1
  sparkle_sign_embedded_bundle "$app_path" "$signing_identity" || return 1

  local sign_args=(
    /usr/bin/codesign
    --force
    --sign "$signing_identity"
    --options runtime
    --timestamp
  )
  if [[ -n "$entitlements_path" ]]; then
    if [[ ! -f "$entitlements_path" ]]; then
      echo "Missing entitlements file: $entitlements_path" >&2
      return 1
    fi
    sign_args+=(--entitlements "$entitlements_path")
  else
    sign_args+=(--preserve-metadata=entitlements,requirements,flags)
  fi
  "${sign_args[@]}" "$app_path"
}

sparkle_create_app_zip() {
  local app_path="$1"
  local zip_path="$2"

  sparkle_require_cmd ditto || return 1
  rm -f "$zip_path"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
}

sparkle_generate_appcast() {
  local archives_dir="$1"
  local private_key_file="$2"
  local download_url_prefix="$3"
  local full_release_notes_url="$4"
  local product_link="$5"
  local maximum_versions="${6:-10}"
  local channel="${7:-}"
  local root_dir="${8:-$(sparkle_repo_root)}"
  local project_path="${9:-$root_dir/Liney.xcodeproj}"
  local scheme="${10:-Liney}"

  local tool_path
  tool_path="$(sparkle_tool_path generate_appcast "$root_dir" "$project_path" "$scheme")" || return 1

  local args=(
    --ed-key-file "$private_key_file"
    --download-url-prefix "$download_url_prefix"
    --embed-release-notes
    --full-release-notes-url "$full_release_notes_url"
    --link "$product_link"
    --maximum-versions "$maximum_versions"
  )
  if [[ -n "$channel" ]]; then
    args+=(--channel "$channel")
  fi

  "$tool_path" "${args[@]}" "$archives_dir"
}
