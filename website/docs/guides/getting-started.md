---
title: Getting Started
---

# Getting Started

Liney is a native macOS workspace for repositories, worktrees, and terminal sessions.

This guide gets you from download to a usable daily setup.

## Download and install

There are two ways to install Liney:

### Homebrew (recommended)

```bash
brew install --cask everettjf/tap/liney
```

### GitHub Releases

Download the latest `.dmg` directly from [GitHub Releases](https://github.com/everettjf/liney/releases). Open the `.dmg` and drag Liney into your Applications folder.

## Add your first repository

Open Liney and add a local repository from the sidebar.

After import, Liney treats that repository as a workspace:

- the workspace appears in the left sidebar
- the active branch and worktree become visible
- you can open sessions without leaving the app

## Learn the core terms

- **Workspace**: the top-level repository container in the sidebar
- **Worktree**: a specific checkout under that repository
- **Session**: a terminal-backed pane running inside a worktree
- **Tab**: a saved arrangement of one or more panes

You do not need to learn every feature up front. Start by opening one workspace and one session.

## Open a session

Create a terminal session from the active workspace or worktree.

Use this when you want to:

- run your app
- start tests
- keep a long-running watcher alive
- open a second shell for Git work

## Use worktrees on purpose

If you work on more than one task at a time, create or switch to a Git worktree instead of stacking unrelated changes in one checkout.

A strong starter setup is:

- one worktree for the main branch
- one worktree for the current feature
- one worktree for review or debugging

## Read the sidebar signals

The sidebar gives you a fast status pass:

- **Current** badge: this is the worktree currently selected for the workspace
- **Green pulse dot**: this worktree has active terminal panes running
- **Changed file badge**: this worktree has uncommitted changes

That means you can spot where work is happening without opening every pane.

## Recommended first workflow

1. Add one repository.
2. Create a feature worktree.
3. Open two sessions in that worktree.
4. Switch back to the main worktree and compare the sidebar state.
