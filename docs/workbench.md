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
```

The fixture uses a unique temporary persistence directory and twelve standalone terminals;
it does not load the user's saved workspaces. The automated variant checks session identity,
process identity and standalone persistence while switching Canvas and Overview. The interactive
variant supports visual/focus checks and stays open until explicitly terminated.

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
- Manual UI/IME checks remain pending: the desktop is locked and computer-use
  cannot inspect or interact with the acceptance window. Do not treat this as a
  completed manual smoke test.

## Handoff / outstanding verification

- Source is on `codex/terminal-workbench`; issue #160 exists. PR publication is
  blocked by automatic approval review, which requires explicit authorization
  to push to the public `everettjf/liney` repository despite verified ADMIN access.
  Do not bypass this gate through another upload mechanism.
- Await desktop unlock for the manual checklist, including actual IME composition,
  text selection, scrolling, focus after expand/return, and sidebar keyboard use.
- The real-surface harness proves surface/session reuse and persistence counts;
  it does not substitute for those manual interaction checks.
