# Liney

[English Version](./README.md)

[![Website](https://img.shields.io/badge/Website-liney.dev-111111?style=flat-square)](https://liney.dev)
[![Releases](https://img.shields.io/badge/Download-GitHub%20Releases-24292f?style=flat-square&logo=github)](https://github.com/everettjf/liney/releases)
[![Platform](https://img.shields.io/badge/Platform-macOS-black?style=flat-square)](https://liney.dev)
[![License](https://img.shields.io/badge/License-Apache%202.0-2ea44f?style=flat-square)](./LICENSE)

Liney 是一款原生 macOS 终端工作区应用，面向需要频繁在多个仓库、worktree、分支和分屏之间切换的开发者。

它把代码库、worktree、终端标签页和分屏布局集中到一个专注的工作空间中，让你不必来回整理一堆 Terminal 窗口，也能保持上下文连续。

![Liney 应用截图](./images/screenshot.png)

## 为什么选择 Liney

- 在同一个侧边栏里管理多个仓库和 worktree。
- 回到某个仓库时，快速恢复上次使用的分屏布局。
- 混合使用本地 shell、SSH 和 agent 驱动的终端会话。
- 在一个围绕键盘高频操作设计的原生 macOS 应用中完成工作。

## 安装

### Homebrew

```bash
brew update && brew install --cask everettjf/tap/liney
```

### 直接下载

从 GitHub Releases 下载最新已签名的 `.dmg`：

<https://github.com/everettjf/liney/releases/latest>

## 快速开始

1. 打开 Liney。
2. 向侧边栏添加一个或多个本地仓库。
3. 选择一个仓库或 worktree，并打开一个终端标签页。
4. 按需拆分面板，并在切换 worktree 时继续沿用已有布局。

## 系统要求

- macOS 14.6 或更高版本
- 当前发布包同时支持 Apple Silicon 和 Intel Mac

## 相关链接

- Website: <https://liney.dev>
- 文档: <https://liney.dev/docs/intro>
- Releases: <https://github.com/everettjf/liney/releases>
- Issues: <https://github.com/everettjf/liney/issues>
- Discord: <https://discord.com/invite/eGzEaP6TzR>

进阶功能：

- [生命周期钩子](https://liney.dev/docs/guides/lifecycle-hooks) — 在应用或会话启动/退出时执行自定义命令

## 分支说明

- `main` — 开发分支，可能不稳定。
- `stable` — 稳定发布分支。如果需要可靠的源代码版本，请使用此分支。

## 面向开发者

开发环境配置、构建命令、测试方式、仓库结构以及发布流程文档位于 [`DEVELOP.md`](./DEVELOP.md)。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=everettjf/liney&type=Date)](https://www.star-history.com/#everettjf/liney&Date)

## 许可证

本项目基于 Apache License 2.0 发布。详见 [`LICENSE`](./LICENSE)。
