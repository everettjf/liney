---
title: Diff and Review
---

# Diff and Review

Liney includes a dedicated diff window because terminal work and code review usually happen together.

## What the diff view gives you

The diff window is built around a changed-file sidebar and a document viewer.

You can:

- browse changed files from a sidebar
- switch between split and unified diff modes
- refresh the current diff
- inspect renamed and copied files clearly

This is useful when you want a focused review pass without leaving the same workspace context that owns the changes.

## Why this matters in Liney

Liney keeps worktree state, sessions, and repository status connected.

That means diff is more useful here than in a disconnected viewer:

- you can see which worktree owns the changes
- you can keep logs or tests running in nearby panes
- you can review without losing the terminal context that produced the change

## Good moments to open diff

- before committing a feature branch
- after switching back into an older worktree
- while cleaning up a review branch
- when the sidebar shows changed files but you need a faster scan than `git diff`

## Suggested review rhythm

1. Keep implementation and test panes open.
2. Open the diff window for a structured file-by-file pass.
3. Fix issues in the terminal panes.
4. Refresh diff and verify the final shape before commit or PR.

This keeps review attached to execution instead of becoming a separate context switch.
