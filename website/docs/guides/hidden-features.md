---
title: Hidden Features
---

# Hidden Features

Liney has a few features that are easy to miss if you only treat it like a terminal launcher.

## The sidebar is a live workspace map

Worktree rows can show:

- the current worktree
- which worktree has active terminal panes
- changed file counts

That makes the sidebar useful as a status dashboard, not just a navigation list.

## Tabs preserve real context

Tabs are not only visual separators.

They preserve pane layout and let you keep different arrangements for the same worktree.

Useful setups:

- coding tab
- run-and-test tab
- debugging tab

## Split panes intentionally

Liney works best when panes represent distinct tasks instead of duplicated shells.

Examples:

- app server on one side, tests on the other
- logs in one pane, fixes in another
- Git commands below a long-running watcher

## Worktree switching is the power feature

Many tools can open shells.

Liney is different because worktree switching stays attached to workspace state, so you can move across related checkouts without rebuilding context every time.

## Diff and overview views are part of the product

If you only use the terminal pane, you miss part of the workflow:

- overview for repository state
- diff views for changed files
- workspace-level visibility across active tasks
