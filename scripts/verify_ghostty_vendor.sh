#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO_ROOT/Liney/Vendor/GhosttyKit.version"
FRAMEWORK="$REPO_ROOT/Liney/Vendor/GhosttyKit.xcframework"
BINARY="$FRAMEWORK/macos-arm64_x86_64/ghostty-internal.a"

# shellcheck disable=SC1090
source "$MANIFEST"

ARCHS="$(lipo -archs "$BINARY")"
for REQUIRED_ARCH in arm64 x86_64; do
    if [[ " $ARCHS " != *" $REQUIRED_ARCH "* ]]; then
        echo "Missing Ghostty architecture: $REQUIRED_ARCH (found: $ARCHS)" >&2
        exit 1
    fi
done

PLIST_ARCHS="$(plutil -extract AvailableLibraries.0.SupportedArchitectures json -o - "$FRAMEWORK/Info.plist")"
for REQUIRED_ARCH in arm64 x86_64; do
    if [[ "$PLIST_ARCHS" != *"$REQUIRED_ARCH"* ]]; then
        echo "Ghostty Info.plist does not advertise: $REQUIRED_ARCH" >&2
        exit 1
    fi
done

if ! grep -aF -q "$GHOSTTY_VERSION" "$BINARY"; then
    echo "Ghostty binary does not contain expected version: $GHOSTTY_VERSION" >&2
    exit 1
fi

BINARY_BYTES="$(stat -f %z "$BINARY")"
if (( BINARY_BYTES >= 100000000 )); then
    echo "Ghostty binary is too large for GitHub: $BINARY_BYTES bytes" >&2
    exit 1
fi

echo "Ghostty vendor verified: $GHOSTTY_VERSION ($ARCHS, $BINARY_BYTES bytes)"
