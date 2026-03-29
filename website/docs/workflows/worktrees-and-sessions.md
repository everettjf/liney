---
title: Worktrees and Sessions
---

# Worktrees and Sessions

Liney is strongest when you use Git worktrees and terminal sessions together.

## Why worktrees matter here

A normal terminal setup makes parallel tasks hard to track:

- one shell is on the wrong branch
- another shell is running in the wrong directory
- a review checkout and a feature checkout blur together

Liney keeps those states visible and grouped under the same workspace.

## A practical model

Think of each worktree as one track of work:

- **Main** for stable commands and release work
- **Feature** for active implementation
- **Review** for checking another branch or PR
- **Debug** for risky experiments you do not want mixed into the feature branch

Each worktree can have its own tabs and pane layout.

## What an active session means

An active session is a live pane attached to a worktree.

Examples:

- app server running
- test watcher running
- shell waiting for input
- logs or build output still visible

When a worktree has active panes, the sidebar shows the animated green activity dot.

## Recommended team workflow

1. Keep one workspace per repository.
2. Create separate worktrees for each active thread.
3. Let each worktree own its sessions.
4. Use the sidebar to re-enter the right context instead of rebuilding it manually.
