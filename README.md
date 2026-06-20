# 红绿灯

一款轻量的 macOS Codex 状态提醒工具。它在菜单栏显示当前状态，并用灵动岛样式的悬浮提示告诉你 Codex 是正在工作、已经完成，还是正在等待权限批准。

> 本项目是非官方工具，与 OpenAI 无隶属或背书关系。

## 功能

- 菜单栏状态图标：`🔴`、`🟢`、`🟡`、`⚪️`
- 灵动岛样式状态提示，不抢占键盘和鼠标焦点
- 支持顶部居中、右下角、左下角三种显示位置
- 支持完全隐藏悬浮提示，仅保留菜单栏图标
- 没有活动会话时自动隐藏悬浮提示
- 支持开机启动
- 原生 Swift + AppKit 实现，无第三方依赖
- 仅在本机读取 Codex 会话记录，不上传数据

## 状态说明

| 图标 | 状态 | 说明 |
| --- | --- | --- |
| `🔴` | 正在工作 | Codex 正在推理、调用工具或输出内容 |
| `🟢` | 工作完成 | Codex 已完成当前任务，提示保留约 45 秒 |
| `🟡` | 等待批准 | Codex 正在等待权限批准 |
| `⚪️` | 空闲 | 当前没有检测到活动的 Codex 会话 |

## 系统要求

- macOS 13 Ventura 或更高版本
- 已安装并使用过 Codex，且本机存在 `~/.codex/sessions` 会话目录

从源码构建还需要 Xcode Command Line Tools（包含 Swift 5.9 或更高版本）。

## 安装

### 使用构建脚本

```bash
git clone <你的 GitHub 仓库地址>
cd "codex 状态提醒"
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open "dist/红绿灯.app"
```

构建完成后，应用位于：

```text
dist/红绿灯.app
```

建议将 `红绿灯.app` 移到 `/Applications` 后再启动，以保证开机启动路径保持稳定。

如果 macOS 阻止首次打开，请在 Finder 中右键应用并选择“打开”，或前往“系统设置 > 隐私与安全性”确认打开。

### 开发运行

```bash
swift run
```

直接使用 `swift run` 时不会创建 `.app`，因此不能安装开机启动项。需要测试完整行为时，请使用构建脚本启动 `dist/红绿灯.app`。

## 使用方法

启动后，应用不会出现在 Dock 中。菜单栏会显示一个状态图标：

1. 点击菜单栏的红绿灯图标查看当前 Codex 状态。
2. 在“显示位置”中选择“顶部居中”“右下角”“左下角”或“不显示”。
3. 勾选或取消“开机启动”。
4. 选择“退出红绿灯”即可完全退出应用。

首次从 `.app` 启动时，应用会默认启用开机启动。对应配置文件为：

```text
~/Library/LaunchAgents/local.codex.status-island.plist
```

## 工作原理

红绿灯每 2 秒读取一次 `~/.codex/sessions` 中最近更新的 Codex JSONL 会话文件，并根据最新会话事件判断状态：

- `task_started`、推理、工具调用、评论输出等事件判定为正在工作。
- `task_complete` 或最终答复事件判定为工作完成。
- 包含权限升级或审批参数的工具调用判定为等待批准。

应用不会通过 Codex 常驻进程、SQLite 修改时间或普通日志推测状态，这可以减少“任务已经结束但仍显示正在工作”的误判。

## 隐私

- 所有状态检测均在本机完成。
- 应用不需要网络连接，也不会上传会话内容。
- 应用只读取最近会话的事件类型和必要参数，用于判断工作状态。

## 项目结构

```text
.
├── Package.swift
├── Sources/CodexStatusIsland/main.swift
├── scripts/build_app.sh
└── README.md
```

## 已知限制

- 状态判断依赖 Codex 当前使用的本地会话事件格式；如果 Codex 后续调整该格式，检测逻辑可能需要同步更新。
- 多个会话同时运行时，当前版本以最近更新的会话文件为准。
- 应用目前未进行 Apple Developer ID 签名和公证，首次打开时可能出现 macOS 安全提示。

## 参与开发

欢迎提交 Issue 或 Pull Request。修改后可使用以下命令确认项目能够正常编译：

```bash
swift build
```

<img width="582" height="172" alt="image" src="https://github.com/user-attachments/assets/f8ba93ea-4c76-484f-be53-05cfacf04d8a" />
<img width="566" height="162" alt="image" src="https://github.com/user-attachments/assets/0433a471-c31a-4c3d-984c-7776cb4391f7" />
<img width="614" height="152" alt="image" src="https://github.com/user-attachments/assets/19e8d7eb-cee7-4b44-bdd4-294131e3271f" />
<img width="438" height="58" alt="image" src="https://github.com/user-attachments/assets/534bdf31-ab59-4fe8-bebc-c60fcfa82b56" />
<img width="357" height="190" alt="image" src="https://github.com/user-attachments/assets/4ddd79e8-0aae-4de2-963f-fd759bab5927" />

