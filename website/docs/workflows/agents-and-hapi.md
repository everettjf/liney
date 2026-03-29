---
title: Agents and HAPI
---

# Agents and HAPI

Liney can launch agent-backed terminal sessions, and it also includes first-class HAPI integration when the `hapi` executable is available on your machine.

## Agent sessions

An agent session in Liney is a terminal-backed session created from a reusable command definition.

Each agent preset can include:

- a display name
- launch path
- arguments
- environment variables
- an optional working directory override

This is useful for tools like Codex or other AI CLIs that you run repeatedly in the same kind of repository context.

## What HAPI integration does

When Liney detects `hapi` in your shell path, HAPI actions become available inside the app.

Liney checks for:

- `hapi`
- `cloudflared` for tunnel-related actions

Once detected, the command palette can offer workspace-aware HAPI actions such as:

- launch HAPI in the current workspace
- start HAPI Hub
- start `hapi hub --relay`

The key detail is that Liney launches HAPI in the active worktree, so the session opens in the repository context you are already using.

## Additional HAPI actions

The app also exposes several HAPI-related commands:

- HAPI Codex
- HAPI Cursor
- HAPI Gemini
- HAPI OpenCode
- HAPI auth status
- HAPI auth login
- HAPI auth logout
- HAPI show settings
- Cloudflared tunnel actions when `cloudflared` is installed

## Why this is useful

Without Liney, launching an agent tool usually means:

- opening another terminal window
- making sure you are in the right directory
- remembering the right command variant

With Liney, the agent session is attached to the workspace and worktree that already own the task.

## A practical HAPI flow

1. Select the workspace or worktree you want to work in.
2. Open the command palette.
3. Launch HAPI in that workspace.
4. If you need relay mode or hub setup, start HAPI Hub from the same workspace-aware actions.

If `hapi` is not installed, those actions stay unavailable, which keeps the UI honest instead of showing broken launchers.
