# Feature Backlog

This document turns the current product discussion into tracked, scoped GitHub issues that fit the existing Liney architecture.

The "agent host" track is captured separately in [agent-host-roadmap.md](./agent-host-roadmap.md).

## Priorities

### P0

- [#38](https://github.com/everettjf/liney/issues/38) Restore `tmux`-backed sessions on relaunch
- [#39](https://github.com/everettjf/liney/issues/39) Add global UI scale controls for non-terminal surfaces
- [#40](https://github.com/everettjf/liney/issues/40) Audit and complete standard macOS keyboard shortcuts
- [#41](https://github.com/everettjf/liney/issues/41) Support side-by-side worktrees in split panes
- [#44](https://github.com/everettjf/liney/issues/44) Add SSH-backed remote session foundations

### P1

- [#42](https://github.com/everettjf/liney/issues/42) Add a multi-worktree overview surface
- [#43](https://github.com/everettjf/liney/issues/43) Add a lightweight built-in text editor for quick edits
- [#45](https://github.com/everettjf/liney/issues/45) Add remote repository browsing and workspace actions

### P2

- [#46](https://github.com/everettjf/liney/issues/46) Profile and improve canvas-heavy UI performance
- [#47](https://github.com/everettjf/liney/issues/47) Define an extension architecture for Liney features

## Dependency Notes

- Shortcut completion in [#40](https://github.com/everettjf/liney/issues/40) is tracked through [#49](https://github.com/everettjf/liney/issues/49), [#50](https://github.com/everettjf/liney/issues/50), and [#51](https://github.com/everettjf/liney/issues/51).
- Remote repository browsing depends on the remote-session foundation in [#44](https://github.com/everettjf/liney/issues/44).
- Multi-worktree overview in [#42](https://github.com/everettjf/liney/issues/42) becomes more valuable after cross-worktree splits in [#41](https://github.com/everettjf/liney/issues/41), but it is still independently shippable.
- Canvas performance work in [#46](https://github.com/everettjf/liney/issues/46) should inform any denser multi-worktree UI before scope expands further.
- Extension architecture in [#47](https://github.com/everettjf/liney/issues/47) is intentionally separated from immediate end-user features so the host boundaries can be designed after the current core workflow gaps are closed.

## Not Tracked Here

- The `Claude Code overloaded_error` report appears to be an upstream service issue rather than a Liney repository problem, so it is intentionally not tracked as a Liney issue.
