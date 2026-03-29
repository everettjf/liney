---
title: Remote Sessions and SSH
---

# Remote Sessions and SSH

Liney can open remote sessions directly from a workspace, so remote shells stay connected to the same repository context as your local work.

## What a remote session includes

When you create an SSH session in Liney, you can define:

- host
- user
- port
- identity file
- remote working directory
- optional remote command

You can also save the connection as a reusable remote target.

Saved targets show up again in future SSH sheets, in the sidebar menu, and in the command palette.

## Why remote targets matter

The useful part is not only "open SSH."

The useful part is that the remote target becomes part of the workspace model:

- each repository can keep its own remote destinations
- the active local worktree still provides context
- remote sessions can be reopened without rebuilding the same command line every time

## Remote repository browser

Liney also has a lightweight repository-browser mode for remote targets.

That mode opens a remote session and starts with a practical overview:

- `pwd`
- `ls -la`
- `git status --short --branch`

Then it drops you into your login shell.

This is a good fit when you want a quick state check before doing deeper work.

## Remote agent sessions

If a remote target is paired with an agent preset, Liney can launch the agent remotely too.

That lets you keep the same idea of:

- repository context
- working directory
- reusable tool launch

even when the session is not local.

## Recommended use cases

- connecting to a Linux host that runs the actual app or jobs
- opening a remote shell in the same repo-specific flow as your local work
- reusing one known-good SSH target instead of rebuilding flags and paths
- launching a remote agent in a prepared working directory
