# Terminal workbench

Tracking issue: https://github.com/everettjf/liney/issues/160

## Product contract

- Standalone terminals live in a separate collapsible sidebar section. New terminals start in Home; explicit directory actions inherit a chosen local directory. Ownership is saved independently of display names. Existing local-folder workspaces retain their previous ownership.
- Standalone terminals use existing Ghostty sessions, tabs and splits. Closing the final tab removes the standalone entry. Layout/directory/history restoration does not promise to resume ordinary shell processes.
- Overview contains needs-attention, continue-working and a searchable directory. Agent states come from reported events. Reading an alert does not resolve it. Dirty files alone are not alerts.
- Overview and Canvas share tab identities, pin state and user-visit timestamps. Background output must not reorder recent work.
- Canvas defaults to a readable scrolling grid; free layout preserves existing saved positions. Visible cards reuse existing terminal surfaces and must never launch dormant tabs simply for browsing.
- Canvas supports direct input, pinning, in-place expansion, return to grid, opening the workspace and creating standalone terminals.
- Repository GitHub status uses the existing CLI service. Failed refreshes preserve prior state with an explicit stale/error indicator; PR and failing-check actions use existing service/coordinator entry points.

## Verification

Build with the repository's `Liney` scheme and `platform=macOS,arch=arm64` destination.
Focused suites: `WorkbenchTests`, `WorkspaceSettingsTests`, `WorkspaceTabsTests`,
`WorkspaceGitHubCoordinatorTests`, `LineyGhosttyInputSupportTests`, `ShellSessionTests`.

Debug builds expose an isolated fixture:

```sh
/path/to/Liney.app/Contents/MacOS/Liney workbench-smoke
/path/to/Liney.app/Contents/MacOS/Liney workbench-smoke --interactive
/path/to/Liney.app/Contents/MacOS/Liney workbench-smoke --interactive --production-ui
```

The fixture uses a unique temporary persistence directory and twelve standalone terminals;
it does not load the user's saved workspaces. The automated variant checks session identity,
surface creation counts and standalone persistence while switching Canvas and Overview. The interactive
variant supports visual/focus checks and stays open until explicitly terminated.
The `--production-ui` variant starts with no workspaces and hosts the actual
main window, toolbar and sheets using the same isolated temporary persistence.

## Release acceptance checklist

- [ ] No-project creation, explicit-directory creation, rename, running-process close protection.
- [ ] Restart restores multiple tabs, splits, selected tab and directory without flattening the layout.
- [ ] Agent waiting/error updates both surfaces and navigates to the reported pane.
- [ ] Dirty plus failed checks yield one attention row for the worktree, with freshness/error labels.
- [ ] Twelve started tabs retain session/process identity across view changes; dormant tabs stay idle.
- [ ] Pin scope, filtering, expansion/return, free-layout compatibility and stable card order.
- [ ] Keyboard navigation, Chinese input/composition, selection, terminal scrolling and splitting.
- [ ] Full build, relevant automated tests and recorded manual smoke results.

The checklist remains open until each scenario is verified; a successful build alone does not establish runtime acceptance.

## Verification record (2026-09-28)

- Debug arm64 macOS build passed with Xcode 27.1.
- Full suite passed: 660 tests. A later focused run covers added launch-layout,
  failed-CI aggregation and legacy shortcut migration tests (61 passed).
- Follow-up standalone close/folder behavior checks: 28 focused tests passed.
- Follow-up attention/navigation checks passed; the latest workbench suite has
  9 passing tests. Free layout now shares status summaries, pin scope and expansion.
  Aggregated rows expose secondary actions so one waiting tab cannot hide another.
- Real Ghostty smoke passed: `surfaces=12 after=12 sessions=12 restored=12` and
  `LINEY_WORKBENCH_SMOKE_OK`.
- After desktop unlock, isolated interactive checks passed: readable two-column
  live grid, shared pin scope in grid/free layout, expansion and return in both
  layouts, Overview waiting-state display and navigation back to the original
  terminal with its output intact. The sidebar showed twelve separate standalone
  entries and exposed rename, create-here, open-as-project and close actions.
- ASCII keyboard input and execution passed. A Chinese paste initially produced
  a computer-use timeout, but subsequent inspection showed the exact pasted text;
  executing it printed `liney-中文-input-ok` correctly. This verifies paste/output,
  not Chinese IME composition. No production input defect was established.
- The fixture does not cover every production sheet/menu. Rename completion,
  actual IME composition, selection, scrolling, split interactions and full
  keyboard navigation remain manual release checks, not completed acceptance.

## Handoff / outstanding verification

### UI follow-up

- Empty standalone sections are hidden; creating a terminal expands the section.
  The sidebar plus was removed. The main toolbar creation menu sits immediately
  before Toggle File Tree, with Home and local-current-directory actions.
- Canvas uses one shared search/layout/scope toolbar. Picker labels are hidden
  visually (retained for accessibility), with compact menu fallback. Free layout
  keeps organize/zoom controls, with archived/project filters in the organize menu.
  Single-pane cards omit redundant inner chrome; split panes retain their headers.
- Overview uses a compact all-clear line, wider small-count recent cards, and
  a collapsed directory instead of repeating every terminal by default.
- Follow-up Debug build and 15 workbench/tab tests passed. An isolated interactive
  fixture verified the single Canvas toolbar, removed inner pane chrome, layout
  switching and collapsed Overview directory. Narrow-window behavior remains a
  release check.

### Menu and production-window acceptance

- Menu labels now distinguish Home from the current directory in English and
  Chinese. The current-directory item shows its target and is disabled without
  an existing local directory.
- Manual testing found stale menu directory capture after `cd`; the toolbar now
  builds its native menu at open time rather than capturing a SwiftUI render's
  directory. Verified `cd /private/tmp` updates the label and new shell `pwd`
  resolves to `/tmp` (the same macOS directory after URL normalization).
- Passed isolated production-window checks: empty sidebar hides Terminals;
  Home creation reveals the group; current-directory creation; rename sheet
  save; `sleep 300` triggers close confirmation; Cancel preserves the running
  session; stopping the command permits closure; final closure hides the group.
- Passed Overview empty state and single-card Canvas pin, expand/return and
  free-layout pinned scope checks. No user workspace was loaded by this fixture.
- Final build/test run passed all 97 workbench, tab and Ghostty input-support
  tests. Repeated real-surface smoke passed with twelve surfaces before/after,
  twelve sessions and twelve restored records. IME composition and exhaustive
  keyboard/selection/scrolling checks are still not claimed as verified.

- Source is on `codex/terminal-workbench`; issue #160 exists. On 2026-09-28,
  the user explicitly authorized pushing this implementation to the public
  `everettjf/liney` repository and creating a PR. Keep the PR in draft until
  the outstanding release checks are complete.
- Finish the remaining production-app manual checklist, including actual IME
  composition, text selection, scrolling, splitting and sidebar keyboard use.
- The real-surface harness proves surface/session reuse and persistence counts;
  it does not substitute for those manual interaction checks.
