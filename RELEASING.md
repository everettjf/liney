# Releasing Liney

## Preconditions

- Clean git worktree
- `gh auth login` completed
- Developer ID signing identity available if signing/notarizing
- Sparkle private key exported locally, usually at `~/.liney_release/sparkle_private_key`
- Metal toolchain installed for Ghostty release builds:

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Versioning

Update the Xcode project version before releasing:

```bash
scripts/bump_version.sh patch
scripts/bump_version.sh minor
scripts/bump_version.sh set 1.2.0
```

The script updates both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
All version bumps skip any semantic version that contains the digit `4` in any component, so `1.0.3` becomes `1.0.5`, `1.3.9` minor-bumps to `1.5.0`, and `3.9.9` major-bumps to `5.0.0`.
Build numbers follow the same rule, so `23` becomes `25` and explicit overrides containing `4` are rejected.
Explicit `set` versions follow the same rule, so values such as `1.2.4`, `1.2.14`, and `1.4.0` are rejected.

## Sparkle Setup

Generate or restore the Sparkle signing key on the machine that will publish releases:

```bash
scripts/setup_sparkle_keys.sh
```

The script prints the public key and exports the private key to `~/.liney_release/sparkle_private_key`. The public key must match `SUPublicEDKey` in the app target.

Because Liney is open source, do not store this private key in the main repository. Prefer one of:

- a private release-infra repository
- a CI/CD secret manager
- a dedicated release machine with `LINEY_RELEASE_HOME` pointing at a protected directory

## Build A Release Bundle

```bash
scripts/build_macos_app.sh
```

Optional environment:

- `SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"`
- `OUTPUT_DIR=/custom/output/path`
- `RELEASE_ARCHS="arm64 x86_64"`

The default release bundle is now a universal macOS artifact that contains both `arm64` and `x86_64` slices.

## Sign And Notarize

Recommended once per release machine:

```bash
xcrun notarytool store-credentials liney-notarytool \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx" \
  --validate
```

```bash
scripts/sign_macos.sh \
  --identity "Developer ID Application: Your Name (TEAMID)" \
  --version 1.0.0 \
  --force-rebuild \
  --notarize
```

Provide notarization credentials with either:

- `NOTARYTOOL_PROFILE=liney-notarytool` (recommended)
- `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`

## Publish

```bash
./deploy.sh
```

If the `liney-notarytool` profile exists in the current keychain, `scripts/sign_macos.sh` and `./deploy.sh` will use it automatically. You only need to pass `NOTARYTOOL_PROFILE` when you want to override that default.

Default behavior:

- bumps `MARKETING_VERSION` by patch and increments `CURRENT_PROJECT_VERSION` by 1 unless `SKIP_BUMP=1`
- builds and signs the universal release DMG
- archives `Liney.app.dSYM` to `dist/dSYMs/Liney-<version>.app.dSYM`
- packages `dist/dSYMs/Liney-<version>.app.dSYM.zip`
- uploads `Liney.app.dSYM` to Sentry using the default target `xnu/liney`
- packages `Liney-<version>.app.zip` for Sparkle
- notarizes unless `SKIP_NOTARIZE=1`
- updates the repository `appcast.xml`
- creates or updates the GitHub release, including the dSYM zip
- updates the Homebrew tap unless `SKIP_CASK_UPDATE=1`

Useful overrides:

- `BUMP_PART=minor ./deploy.sh`
- `SKIP_BUMP=1 ./deploy.sh`
- `SKIP_NOTARIZE=1 ./deploy.sh`
- `SKIP_CASK_UPDATE=1 ./deploy.sh`
- `SKIP_SENTRY_DSYM_UPLOAD=1 ./deploy.sh`
- `LINEY_RELEASE_HOME=/secure/release-home ./deploy.sh`
- `SPARKLE_PRIVATE_KEY_FILE=/secure/path/private_key ./deploy.sh`

Sentry dSYM upload uses `sentry-cli` authentication by default. `SENTRY_AUTH_TOKEN` also works.

Optional Sentry environment:

- `SENTRY_ORG` to override the default org `xnu`
- `SENTRY_PROJECT` to override the default project `liney`
- `SENTRY_URL` for self-hosted Sentry
- `SENTRY_INCLUDE_SOURCES=1` to upload source bundles together with the dSYM

If you prefer the old path, `scripts/deploy.sh` remains available as a compatibility wrapper.

For the first public release, prefer writing the GitHub release notes manually instead of relying only on generated commit summaries.
