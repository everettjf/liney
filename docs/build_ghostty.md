# Rebuild GhosttyKit.xcframework

This note records the current manual process for rebuilding the vendored `Liney/Vendor/GhosttyKit.xcframework`.

Liney does not currently generate this framework in-repo. The xcframework is vendored into source control and updated manually when the embedded Ghostty runtime needs to change.

## What This Framework Is

Liney links against Ghostty's macOS library through `GhosttyKit.xcframework`.

Ghostty's upstream build system can emit an xcframework directly. In current upstream source:

- `app-runtime=none` means "build the library for a macOS app consumer" rather than a standalone Ghostty app runtime.
- `emit-xcframework=true` enables xcframework output.
- `xcframework-target=universal` produces a universal macOS library. Current upstream emits only the macOS slice for this target.

Relevant upstream sources:

- Ghostty build docs: <https://ghostty.org/docs/install/build>
- Ghostty build config: <https://raw.githubusercontent.com/ghostty-org/ghostty/main/src/build/Config.zig>
- Ghostty xcframework builder: <https://raw.githubusercontent.com/ghostty-org/ghostty/main/src/build/GhosttyXCFramework.zig>
- Ghostty runtime enum: <https://raw.githubusercontent.com/ghostty-org/ghostty/main/src/apprt/runtime.zig>

## Important Constraints

- Prefer a specific Ghostty release tag or pinned commit. Do not vendor from upstream `main` casually.
- Ghostty requires a specific Zig version per Ghostty release. Check the official build docs before building.
- The current Liney release flow expects the macOS library slice to contain both `arm64` and `x86_64`.
- Replacing only the binary without the matching headers is risky because the C API surface can change between Ghostty revisions.

## Prerequisites

- macOS with full Xcode installed
- Active developer directory pointing at Xcode, not Command Line Tools
- macOS and iOS SDKs installed in Xcode
- Zig version matching the Ghostty version being built
- `gettext` installed, for example via Homebrew
- Metal toolchain installed

Example setup:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -downloadComponent MetalToolchain
xcrun --kill-cache
brew install gettext
```

`xcrun --kill-cache` is useful after installing the Metal toolchain because
Xcode can otherwise continue resolving the placeholder `metal` executable.

## Fetch Upstream Source

For stable rebuilds, prefer Ghostty's source tarball or a pinned release tag.

Tarball example:

```bash
curl -LO https://release.files.ghostty.org/VERSION/ghostty-VERSION.tar.gz
tar -xf ghostty-VERSION.tar.gz
cd ghostty-VERSION
```

Git example:

```bash
git clone https://github.com/ghostty-org/ghostty
cd ghostty
git checkout <tag-or-commit>
```

The currently vendored build uses:

- Ghostty commit: `602497e9b96c62b05c4c6418538192ad974e4326`
- Ghostty version string: `1.3.2-main+602497e`
- Source archive SHA-256: `7164678225d3c9c45e214c5081108547333cb31ec9f18f6a918471b73f68a5ad`
- Zig: `0.16.0`

## Build The XCFramework

Run Ghostty's Zig build with the macOS app runtime disabled and xcframework output enabled:

```bash
zig build \
  -Doptimize=ReleaseFast \
  -Dapp-runtime=none \
  -Demit-xcframework=true \
  -Demit-macos-app=false \
  -Dxcframework-target=universal \
  -Dversion-string=1.3.2-main+602497e
```

Expected output:

```text
macos/GhosttyKit.xcframework
```

Upstream currently writes the xcframework directly to `macos/GhosttyKit.xcframework`
in the Ghostty source tree. Its macOS archive is named `ghostty-internal.a`.

Strip debug symbols from the static archive before vendoring it. Current
upstream builds otherwise exceed GitHub's 100 MB per-file limit:

```bash
strip -S macos/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a
```

## Replace The Vendored Framework

From the Liney repository root:

```bash
rsync -a --delete \
  /path/to/ghostty/macos/GhosttyKit.xcframework/ \
  Liney/Vendor/GhosttyKit.xcframework/
```

Update the matching selected themes and `xterm-ghostty` terminfo entry as
needed. Do not copy upstream shell integration blindly: recent upstream
versions route SSH through the standalone `ghostty +ssh` CLI, while Liney
embeds the library and does not bundle that executable.

## Verify The Result

Confirm the macOS library is universal:

```bash
lipo -archs Liney/Vendor/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a
```

Expected output:

```text
x86_64 arm64
```

Confirm the xcframework metadata advertises the same architecture set:

```bash
plutil -p Liney/Vendor/GhosttyKit.xcframework/Info.plist
```

Then verify Liney still builds:

```bash
scripts/build_macos_app.sh
```

If you only need a local macOS debug build, an `arm64`-only Ghostty library may still compile on Apple Silicon, but it will break the repository's current universal release flow.

## Update Notes For Maintainers

When refreshing `GhosttyKit.xcframework`, record these details in the commit or PR description:

- Ghostty source version or commit
- Zig version used
- Whether the macOS slice is `arm64 + x86_64`
- Whether the public headers changed
