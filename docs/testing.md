<!--
  testing.md
  Liney

  Author: everettjf
-->

# Testing Guide

This repository leans on focused unit tests instead of broad integration fixtures. Good tests here should make state transitions and parsing rules obvious, stay cheap to run, and avoid coupling to AppKit rendering details unless the behavior truly depends on them.

## What Good Tests Look Like

- Test one behavior branch at a time.
- Name tests around the user-visible or state-visible outcome.
- Prefer deterministic in-memory fixtures over shelling out or touching real repositories.
- Use small fake collaborators when a service depends on `@MainActor` callbacks or controller protocols.
- Assert the specific state transition that matters, not every field in the object.

## Where Tests Usually Belong

- `Tests/GitRepositoryServiceTests.swift`
  For git output parsing, branch selection, ahead/behind, and worktree discovery.
- `Tests/PaneLayoutTests.swift`
  For split trees, pane movement, zoom state, and layout persistence rules.
- `Tests/ShellSessionTests.swift`
  For session lifecycle, controller callbacks, and launch/restart behavior.
- `Tests/LineyGhosttyInputSupportTests.swift`
  For keyboard routing, modifier translation, IME marked-text helpers, and other pure Ghostty adapter logic.

## Preferred Patterns

### Keep parsing tests string-driven

For git parsing logic, pass raw command output into pure helpers and assert the parsed model. That keeps tests stable and independent from the local machine.

### Use fakes for session/controller tests

`ShellSessionTests` uses a fake `ManagedTerminalSessionSurfaceController` to drive exit callbacks and restart behavior without creating a real terminal surface. Prefer this style whenever the unit under test only needs protocol conformance.

### Isolate pure terminal adapter logic

The Ghostty adapter exposes several pure helpers such as:

- `LineyGhosttyTextInputRouting.shouldPreferRawKeyEvent`
- `ghosttyShouldAttemptMenu`
- `resolveGhosttyEquivalentKey`
- `LineyGhosttyMarkedTextState`

These are good candidates for direct unit tests because they encode tricky keyboard and IME rules without requiring a live `NSView`.

## Scope Guidelines

- Add or update tests when changing git parsing, worktree behavior, pane layout rules, persistence, command palette ranking, or terminal adapter logic.
- A plain refactor that only renames types or moves files should still keep at least one targeted test run in the verification notes.
- UI-only visual polish does not always need a new unit test, but it should call out any manual smoke test that was performed.

## Running Tests

Run the full test suite:

```bash
xcodebuild \
  -project Liney.xcodeproj \
  -scheme Liney \
  -destination 'platform=macOS' \
  test
```

Run just the Ghostty input-support tests:

```bash
xcodebuild \
  -project Liney.xcodeproj \
  -scheme Liney \
  -destination 'platform=macOS' \
  test \
  -only-testing:LineyTests/LineyGhosttyInputSupportTests
```

CI also maintains an older-system regression matrix:

- macOS 14 with Xcode 16.2 builds the app at its supported deployment target.
- macOS 15 with Xcode 26.3 runs the full unit-test suite and exercises Swift
  concurrency back-deployment behavior.

Terminal diagnostics retain one hour of non-input events. Refresh, display
metrics, resize, IME composition lengths, scrollback reads, and session/surface
lifecycle entries include pane and session identifiers. The diagnostics window
can export a report or open a prefilled GitHub issue while revealing the report
file in Finder for attachment.

## Review Checklist

Before sending a test-heavy change for review, check:

- The test fails for the broken behavior and passes for the intended behavior.
- The test names explain the branch being covered.
- Fixtures are local to the file unless they are reused enough to justify extraction.
- The assertions are not overspecified.
