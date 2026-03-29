# Develop Liney

This guide is for contributors and maintainers working on the Liney codebase.

## Requirements

- macOS 14+
- Xcode 16+ with command line tools
- `gh` is optional and only needed for GitHub features and release publishing

Release builds also require the Metal toolchain component used by Ghostty:

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Build

```bash
xcodebuild \
  -project Liney.xcodeproj \
  -scheme Liney \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## Test

```bash
xcodebuild \
  -project Liney.xcodeproj \
  -scheme Liney \
  -destination 'platform=macOS' \
  test
```

## Run The Debug Build

```bash
open ~/Library/Developer/Xcode/DerivedData/Liney-*/Build/Products/Debug/Liney.app
```

## Project Layout

```text
Liney/
├─ App/
├─ Domain/
├─ Persistence/
├─ Services/
│  ├─ Git/
│  ├─ Process/
│  └─ Terminal/
│     └─ Ghostty/
├─ Support/
├─ UI/
└─ Vendor/
```

## Docs

- Testing guide: [`docs/testing.md`](./docs/testing.md)
- Terminal architecture: [`docs/terminal-architecture.md`](./docs/terminal-architecture.md)
- Ghostty vendor rebuild: [`docs/build_ghostty.md`](./docs/build_ghostty.md)
- Feature backlog: [`docs/feature-backlog.md`](./docs/feature-backlog.md)
- Release process: [`RELEASING.md`](./RELEASING.md)
- Contributing guide: [`CONTRIBUTING.md`](./CONTRIBUTING.md)
- Security policy: [`SECURITY.md`](./SECURITY.md)

## Data

Liney stores workspace state and app settings in `~/.liney/`, and still reads legacy state from `~/Library/Application Support/Liney/` when present.

## Release Build

```bash
scripts/build_macos_app.sh
open dist/Liney.app
```

Optional variables:

- `SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"` to sign the `.app`
- `OUTPUT_DIR=/custom/output/path` to change the output folder
- `RELEASE_ARCHS="arm64 x86_64"` to override the default universal macOS artifact

The committed `GhosttyKit.xcframework` now includes both macOS `arm64` and `x86_64` slices, so the default release build emits a universal app bundle and DMG.

If you need to rebuild the vendored Ghostty xcframework, see [`docs/build_ghostty.md`](./docs/build_ghostty.md).

The build script emits:

- `dist/Liney.app`
- `dist/Liney-<version>.dmg`

## Auto Updates

Liney uses Sparkle for signed app updates.

To prepare the signing key on a release machine:

```bash
scripts/setup_sparkle_keys.sh
```

This exports the private key to `~/.liney_release/sparkle_private_key` and prints the public key that must stay in the app target's `SUPublicEDKey`.

Because Liney is open source, keep the private key outside this repository. A private release-infra repo, CI secret store, or dedicated release machine is the right place for it.

## Publish

The root release entrypoint is:

```bash
./deploy.sh
```

By default it:

- bumps the patch version
- increments the build number by 1
- signs and notarizes universal release artifacts
- updates GitHub releases, Sparkle appcast metadata, and the Homebrew tap

`scripts/deploy.sh` still exists as a compatibility wrapper.

## Current Limitations

- The main supported local development path is the Xcode project
- Ghostty is required for the terminal stack
- Worktree switching restarts active panes after confirmation so their cwd always matches the newly selected worktree
- Session persistence restores per-worktree layout, zoom state, and pane cwd, but relaunch still recreates fresh shell processes
- Some GitHub workflow features expect `gh` to be installed and authenticated
