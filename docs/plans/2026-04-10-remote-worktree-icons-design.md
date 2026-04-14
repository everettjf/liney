# Remote Worktree & Icons Design

Date: 2026-04-10

## Overview

扩展远程工作区功能，使其达到与本地工作区一致的体验：语义图标生成、完整的 git worktree 管理、独立的 per-worktree 会话状态。

## Decisions

| Decision | Choice |
|----------|--------|
| 实现方案 | 方案 A：增量扩展现有远程检查 |
| 图标策略 | 远程工作区复用本地语义图标生成，保留蓝色 Remote badge |
| Worktree 功能范围 | 完整管理 + 每个 worktree 独立会话 |
| 远程刷新间隔 | 5 秒 |
| Worktree 创建/删除 UI | 与本地完全一致 |

## Part 1: 远程 Git 检查扩展

### SSH 命令扩展

在现有 `inspectRemoteRepository` 的 SSH 命令中追加 `git worktree list --porcelain`：

```bash
cd <path> &&
  echo __BRANCH__ && git rev-parse --abbrev-ref HEAD &&
  echo __HEAD__ && git rev-parse --short HEAD &&
  echo __WORKTREE__ && git worktree list --porcelain &&
  echo __STATUS__ && git status --porcelain &&
  echo __AHEAD_BEHIND__ && git rev-list --left-right --count HEAD...@{upstream} || true
```

### 返回类型变更

`RemoteGitSnapshot` 新增 `worktrees: [WorktreeModel]` 字段。

### 解析逻辑

`parseRemoteInspection` 新增 `__WORKTREE__` 段解析，复用现有 `parseWorktreeList` 方法。

## Part 2: 远程工作区图标

### 图标生成路径统一

- 远程工作区进入 `SidebarIconCatalog` 语义匹配流程
- 种子：远程仓库目录名（`remoteWorkingDirectory` 最后一段）
- 关键词匹配：api→server.rack, web→globe 等，与本地一致

### 远程 worktree 图标

- 复用 `generatedWorktreeIcons`
- 种子：worktree 分支名/路径

### Remote badge 保留

- 现有蓝色 Remote 标识不变
- 图标与 badge 独立

### 用户自定义

- 远程工作区和 worktree 同样支持 `workspaceIcon` / `worktreeIconOverrides` 手动覆盖

## Part 3: 远程 Worktree 完整管理

### 展示与切换

- 远程刷新后将 worktree 列表写入 `WorkspaceModel.worktrees`
- 侧边栏展开显示所有 worktree
- 切换 worktree 时更新 `activeWorktreePath`，SSH 会话工作目录跟随变化
- 每个 worktree 保存独立的 `WorktreeSessionStateRecord`

### 创建

- UI 与本地一致（分支名、路径输入）
- SSH 执行：`cd <repoRoot> && git worktree add -b <branch> <path> HEAD` 或 `git worktree add <path> <branch>`
- 执行后立即触发远程刷新

### 删除

- UI 与本地一致的确认流程
- SSH 执行：`cd <repoRoot> && git worktree remove <path>`（支持 `--force`）
- 删除后立即刷新

### 独立会话

- `WorkspaceSessionController` 按 worktree 管理会话
- 远程 worktree pane 默认使用 `.ssh` 后端，工作目录为 worktree 远程路径
- 切换 worktree 时保存/恢复状态，与本地行为一致

### Per-worktree Git 状态

- 每个 worktree 独立查询 `git status`
- 结果存入 `worktreeStatuses`
- 侧边栏显示各 worktree 变更数

## Part 4: 轮询策略调整

### 刷新间隔

- `remoteRefreshInterval` 从 30 秒改为 5 秒

### 并发保护

- 保留重入保护（`isRefreshingRemotes`）
- 上一次刷新未完成时跳过当轮

## Key Files

| 文件 | 改动 |
|------|------|
| `GitRepositoryService.swift` | 扩展 SSH 命令、解析逻辑、新增远程 worktree CRUD |
| `WorkspaceModels.swift` | `RemoteGitSnapshot` 增加 worktrees 字段 |
| `WorkspaceStore.swift` | 刷新间隔改 5 秒、远程刷新写入 worktrees、图标生成 |
| `SidebarIconCatalog.swift` | 确保远程工作区走语义图标路径（可能无需改动） |
| 侧边栏相关 UI | 远程 worktree 展示、创建/删除 UI 入口 |
