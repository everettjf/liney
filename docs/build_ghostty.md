# Rebuild GhosttyKit.xcframework

This note records the current manual process for rebuilding the vendored `Liney/Vendor/GhosttyKit.xcframework`.

Liney does not currently generate this framework in-repo. The xcframework is vendored into source control and updated manually when the embedded Ghostty runtime needs to change.

## What This Framework Is

Liney links against Ghostty's macOS library through `GhosttyKit.xcframework`.

Ghostty's upstream build system can emit an xcframework directly. In current upstream source:

- `app-runtime=none` means "build the library for a macOS app consumer" rather than a standalone Ghostty app runtime.
- `emit-xcframework=true` enables xcframework output.
- `xcframework-target=universal` produces a universal macOS library. The pinned upstream build emits a macOS slice for this target.

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

The currently vendored build uses a pinned upstream main commit to include
recent rendering, GPU lifecycle, and terminal fixes while investigating TUI
stalls ([#162](https://github.com/everettjf/liney/issues/162)). This upgrade is
not a confirmed fix for the reported hangs.

These values are also recorded in `Liney/Vendor/GhosttyKit.version`; update
that manifest together with the framework so CI can verify the binary.

- Ghostty commit: `8f0dd3709050b1026f6324368805033197d8b4a5`
- Ghostty version string: `1.3.2-main+8f0dd37`
- Source archive SHA-256: `f4869fc667ea0a1c93705e363ceca06d394b67ad1d3dde756a7fa5c15691f9cb`
- Zig: `0.16.0`

## Build The XCFramework

To rebuild the exact runtime recorded in `Liney/Vendor/GhosttyKit.version`, run:

```bash
bash scripts/build_ghostty_vendor.sh
```

The manifest pins the source URL, commit, version, source SHA-256, Zig version,
and both host-toolchain checksums. The script verifies downloads, builds both
macOS architectures, strips debug symbols, and vendors the matching embedding
headers and binary. The `Rebuild vendored Ghostty` workflow provides an Xcode
26.3 environment and checks Liney compilation and terminal lifecycle.

This commit requires Zig 0.16.0, which also supports newer Xcode SDKs. The old
Zig 0.15.2/Xcode 26.4 linker limitation does not apply to this build.

Run Ghostty's Zig build with the macOS app runtime disabled and xcframework output enabled:

```bash
zig build \
  -Doptimize=ReleaseFast \
  -Dapp-runtime=none \
  -Demit-xcframework=true \
  -Demit-macos-app=false \
  -Dxcframework-target=universal \
  -Dversion-string=1.3.2-main+8f0dd37
```

Expected output:

```text
macos/GhosttyKit.xcframework
```

The pinned upstream build writes the xcframework directly to
`macos/GhosttyKit.xcframework` in the source tree. Its macOS archive is named
`ghostty-internal.a`. Liney uses `ghostty.h` and `module.modulemap`; the separate
VT API headers are not bundled.

Strip debug symbols from the static archive before vendoring it. Current
upstream builds otherwise exceed GitHub's 100 MB per-file limit:

```bash
strip -S macos/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a
```

## Replace The Vendored Framework

From the Liney repository root:

```bash
xcodebuild -create-xcframework \
  -library /path/to/ghostty/macos/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a \
  -headers /path/to/ghostty/macos/GhosttyKit.xcframework/macos-arm64_x86_64/Headers \
  -output /tmp/GhosttyKit-macOS.xcframework
rsync -a --delete \
  /tmp/GhosttyKit-macOS.xcframework/ \
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

Run the repository's complete vendor check (architectures, embedded version,
and GitHub file-size limit):

```bash
scripts/verify_ghostty_vendor.sh
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
