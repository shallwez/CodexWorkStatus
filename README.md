# 红绿灯

一个轻量 macOS 后台悬浮窗，用菜单栏上方居中的灵动岛样式显示 Codex 会话状态。

- 菜单栏状态项：`🔴` / `🟢` / `🟡` / `⚪️`
- 菜单里可以勾选/取消勾选 `开机启动`
- 红色：Codex 正在工作
- 绿色：Codex 工作完成
- 黄色：Codex 等待权限批准
- 没有 Codex 会话活动：自动隐藏

## 开发运行

```bash
swift run
```

## 打包成 App

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open "dist/红绿灯.app"
```

App 用 `LSUIElement` 后台运行，不显示 Dock 图标。第一次从 `.app` 启动后，会默认写入：

```text
~/Library/LaunchAgents/local.codex.status-island.plist
```

下次登录 macOS 时会自动后台启动。

## 状态检测

App 只按 Codex 会话活动状态检测，读取本机 `~/.codex/sessions` 下的最近会话文件：

- `task_started`、推理、工具调用、输出中：显示红色
- `task_complete` 或最终答复：显示绿色 45 秒，然后隐藏
- 最近会话中的真实工具调用审批信号：显示黄色

不会通过 Codex 常驻进程、sqlite 更新时间或普通日志判断状态。
