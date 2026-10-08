#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/liney-ghostty-stable.XXXXXX")"
trap 'rm -rf "$BUILD_ROOT"' EXIT
cd "$BUILD_ROOT"

# Zig 0.15.2 cannot link the SDK shipped with Xcode 26.4 and newer.
XCODE_VERSION="$(xcodebuild -version | awk 'NR == 1 {print $2}')"
case "$XCODE_VERSION" in
  26.[0123]|26.[0123].*) ;;
  *) echo "Use Xcode 26.3 to rebuild Ghostty 1.3.1 (found $XCODE_VERSION)." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64) ZIG_ARCH=aarch64; ZIG_SHA=3cc2bab367e185cdfb27501c4b30b1b0653c28d9f73df8dc91488e66ece5fa6b ;;
  x86_64) ZIG_ARCH=x86_64; ZIG_SHA=375b6909fc1495d16fc2c7db9538f707456bfc3373b14ee83fdd3e22b3d43f7f ;;
  *) echo "Unsupported host architecture" >&2; exit 1 ;;
esac

curl -fL --retry 3 https://release.files.ghostty.org/1.3.1/ghostty-1.3.1.tar.gz -o ghostty.tar.gz
echo '3349d25600ffbda281197a18314f7d18791969cffe9474f0ff16a45a9ebfccdb  ghostty.tar.gz' | shasum -a 256 -c -
curl -fL --retry 3 "https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-macos-0.15.2.tar.xz" -o zig.tar.xz
echo "$ZIG_SHA  zig.tar.xz" | shasum -a 256 -c -
tar -xf ghostty.tar.gz
tar -xf zig.tar.xz
cd ghostty-1.3.1
export PATH="$(brew --prefix gettext)/bin:$PATH"
"$BUILD_ROOT/zig-${ZIG_ARCH}-macos-0.15.2/zig" build \
  -Doptimize=ReleaseFast -Dapp-runtime=none -Demit-xcframework=true \
  -Demit-macos-app=false -Dxcframework-target=universal -Dversion-string=1.3.1
# The 1.3.1 universal output includes iOS slices and names its archive
# libghostty.a. Package only the macOS slice needed by Liney.
MACOS_SLICE="$BUILD_ROOT/ghostty-1.3.1/macos/GhosttyKit.xcframework/macos-arm64_x86_64"
strip -S "$MACOS_SLICE/libghostty.a"
# Match Liney's existing embedding module; the separate VT API is unused.
mkdir "$BUILD_ROOT/EmbeddingHeaders"
cp "$MACOS_SLICE/Headers/ghostty.h" "$MACOS_SLICE/Headers/module.modulemap" "$BUILD_ROOT/EmbeddingHeaders/"
xcodebuild -create-xcframework -library "$MACOS_SLICE/libghostty.a" \
  -headers "$BUILD_ROOT/EmbeddingHeaders" -output "$BUILD_ROOT/GhosttyKit.xcframework"
rsync -a --delete "$BUILD_ROOT/GhosttyKit.xcframework/" "$REPO_ROOT/Liney/Vendor/GhosttyKit.xcframework/"
cat > "$REPO_ROOT/Liney/Vendor/GhosttyKit.version" <<'EOF'
GHOSTTY_COMMIT=332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28
GHOSTTY_VERSION=1.3.1
GHOSTTY_SOURCE_SHA256=3349d25600ffbda281197a18314f7d18791969cffe9474f0ff16a45a9ebfccdb
GHOSTTY_ZIG_VERSION=0.15.2
EOF
bash "$REPO_ROOT/scripts/verify_ghostty_vendor.sh"
