# Liney

[中文版本](./README.zh-CN.md)

[![Website](https://img.shields.io/badge/Website-liney.dev-111111?style=flat-square)](https://liney.dev)
[![Releases](https://img.shields.io/badge/Download-GitHub%20Releases-24292f?style=flat-square&logo=github)](https://github.com/everettjf/liney/releases)
[![Platform](https://img.shields.io/badge/Platform-macOS-black?style=flat-square)](https://liney.dev)
[![License](https://img.shields.io/badge/License-Apache%202.0-2ea44f?style=flat-square)](./LICENSE)

Liney is a native macOS terminal workspace app for developers who work across repositories, worktrees, branches, and split panes.

It gives you one focused place to open codebases, switch worktrees, keep terminal layouts around, and move faster without juggling a pile of Terminal windows.

![Liney app screenshot](./images/screenshot.png)

## Why Use Liney

- Keep multiple repositories and worktrees in one sidebar.
- Reopen the same pane layout when you come back to a repo.
- Mix local shell, SSH, and agent-backed terminal sessions.
- Stay in a native macOS app built around keyboard-heavy workflows.

## Install

### Homebrew

```bash
brew update && brew install --cask everettjf/tap/liney
```

### Direct Download

Download the latest signed `.dmg` from GitHub Releases:

<https://github.com/everettjf/liney/releases/latest>

## Quick Start

1. Open Liney.
2. Add one or more local repositories to the sidebar.
3. Select a repository or worktree and open a terminal tab.
4. Split panes as needed and switch worktrees without rebuilding your layout from scratch.

## Requirements

- macOS 14.6 or later
- Universal build: Apple Silicon and Intel Macs are both supported

## Links

- Website: <https://liney.dev>
- Releases: <https://github.com/everettjf/liney/releases>
- Issues: <https://github.com/everettjf/liney/issues>
- Discord: <https://discord.com/invite/eGzEaP6TzR>

## Branches

- `main` — development branch, may be unstable.
- `stable` — stable release branch. Use this if you need a reliable version of the source code.

## For Developers

Development setup, build commands, testing, repo layout, and release docs live in [`DEVELOP.md`](./DEVELOP.md).

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=everettjf/liney&type=Date)](https://www.star-history.com/#everettjf/liney&Date)

## License

Released under the Apache License 2.0. See [`LICENSE`](./LICENSE).
