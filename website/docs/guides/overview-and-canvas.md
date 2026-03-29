---
title: Overview and Canvas
---

# Overview and Canvas

Liney has two higher-level views that matter once you track more than one repository: Overview and Canvas.

They solve different problems.

- **Overview** helps you decide what needs attention.
- **Canvas** helps you see live terminal context across workspaces.

## Overview is the management surface

The Overview surface summarizes activity across all tracked workspaces.

It includes:

- summary metrics for workspaces, dirty repositories, failing checks, and active sessions
- quick workflow launchers
- a recent activity timeline with replay
- a worktree panel
- focus lists for active work
- pull request inbox and blocker sections

This is the place to answer questions like:

- which repo is dirty right now
- where CI is failing
- which worktree still needs review
- what should I run next

## Canvas is the live layout surface

Canvas is different. It is not a static dashboard.

It shows live terminal cards pulled from your open tabs and sessions. You can:

- browse cards across workspaces
- search by workspace, worktree, tab, or path
- filter by workspace
- pin important cards
- minimize cards that should stay visible but not dominant
- organize cards by workspace or as a grid
- zoom and fit the whole canvas

## When to use each one

Use **Overview** when you want coordination and prioritization.

Use **Canvas** when you want spatial awareness across many active terminals.

## A practical pattern

This pattern works well for multi-repo work:

1. Start in Overview to see blockers and the next workflow to run.
2. Jump into a workspace.
3. Use Canvas when you need to compare several live tabs at once.
4. Return to Overview when you want to regroup and decide what ships next.

The key idea is that Liney is not only a place to open shells. It is also a place to manage active work at repository scale.
