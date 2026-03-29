---
title: Command Palette and Quick Commands
---

# Command Palette and Quick Commands

Liney is built for keyboard-heavy work. The command palette is not only a launcher. It is the fastest way to move between repositories, sessions, workflows, and automation.

## What the command palette is for

The palette can surface actions across the whole app, including:

- opening a workspace
- creating a new terminal session
- splitting the focused pane
- running setup or run scripts
- running a preferred workflow
- opening the overview surface
- creating SSH and agent sessions
- launching HAPI when it is installed

In practice, this turns Liney into a workspace control center instead of a plain terminal shell.

## How to think about it

Treat the palette as the answer to "what should I do next in this repository?"

Examples:

- switch to another workspace without touching the sidebar
- start a new split when you want logs next to code
- re-run a setup script after changing branches
- launch a saved workflow that opens local and agent sessions together

## Quick Commands are reusable snippets

Liney also ships with a Quick Commands system for terminal commands you run often.

The built-in library is organized into categories such as:

- Codex
- Claude
- Git
- Search
- Files
- Network
- Processes
- Homebrew
- macOS

You can keep these as a command reference, or use them as the starting point for your own shortcuts.

## Good uses for Quick Commands

- opening an AI CLI with the same arguments every time
- checking ports, processes, or disk usage
- running a multi-step Git inspection command
- keeping a command you only remember after searching your shell history

## Recommended setup

1. Use the command palette for navigation and app-level actions.
2. Use Quick Commands for terminal commands you want to insert or reuse.
3. Save the commands you repeatedly paste from notes or shell history.

That split keeps Liney fast: the palette decides what to do in the app, and Quick Commands decide what to run in the shell.
