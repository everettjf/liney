#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1090
source "$REPO_ROOT/Liney/Vendor/GhosttyKit.version"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/liney-ghostty-vendor.XXXXXX")"
trap 'rm -rf "$BUILD_ROOT"' EXIT
cd "$BUILD_ROOT"

case "$(uname -m)" in
  arm64) ZIG_ARCH=aarch64; ZIG_SHA="$GHOSTTY_ZIG_AARCH64_SHA256" ;;
  x86_64) ZIG_ARCH=x86_64; ZIG_SHA="$GHOSTTY_ZIG_X86_64_SHA256" ;;
  *) echo "Unsupported host architecture" >&2; exit 1 ;;
esac

curl -fL --retry 3 "$GHOSTTY_SOURCE_URL" -o ghostty.tar.gz
echo "$GHOSTTY_SOURCE_SHA256  ghostty.tar.gz" | shasum -a 256 -c -
curl -fL --retry 3 "https://ziglang.org/download/$GHOSTTY_ZIG_VERSION/zig-${ZIG_ARCH}-macos-$GHOSTTY_ZIG_VERSION.tar.xz" -o zig.tar.xz
echo "$ZIG_SHA  zig.tar.xz" | shasum -a 256 -c -
mkdir source
tar -xf ghostty.tar.gz --strip-components=1 -C source
tar -xf zig.tar.xz
cd source
export PATH="$(brew --prefix gettext)/bin:$PATH"
"$BUILD_ROOT/zig-${ZIG_ARCH}-macos-$GHOSTTY_ZIG_VERSION/zig" build \
  -Doptimize=ReleaseFast -Dapp-runtime=none -Demit-xcframework=true \
  -Demit-macos-app=false -Dxcframework-target=universal -Dversion-string="$GHOSTTY_VERSION"
MACOS_SLICE="$BUILD_ROOT/source/macos/GhosttyKit.xcframework/macos-arm64_x86_64"
strip -S "$MACOS_SLICE/ghostty-internal.a"
# Liney uses the embedding API, not the separate VT API.
mkdir "$BUILD_ROOT/EmbeddingHeaders"
cp "$MACOS_SLICE/Headers/ghostty.h" "$MACOS_SLICE/Headers/module.modulemap" "$BUILD_ROOT/EmbeddingHeaders/"
# Upstream comments can contain trailing spaces; keep vendored diffs lint-clean.
perl -pi -e 's/[ \t]+$//' "$BUILD_ROOT/EmbeddingHeaders/ghostty.h"
xcodebuild -create-xcframework -library "$MACOS_SLICE/ghostty-internal.a" \
  -headers "$BUILD_ROOT/EmbeddingHeaders" -output "$BUILD_ROOT/GhosttyKit.xcframework"
rsync -a --delete "$BUILD_ROOT/GhosttyKit.xcframework/" "$REPO_ROOT/Liney/Vendor/GhosttyKit.xcframework/"
bash "$REPO_ROOT/scripts/verify_ghostty_vendor.sh"
