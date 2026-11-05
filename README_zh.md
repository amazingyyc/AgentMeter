<p align="center">
  <img src="./Resources/AppIcon.png" width="112" height="112" alt="Agent Meter Logo" />
</p>

<h1 align="center">Agent Meter</h1>

<p align="center">
  <a href="./README.md">English</a> | 简体中文
</p>

<p align="center">
  <img src="./Resources/demo.webp" width="100%" alt="Agent Meter 动态演示" />
</p>

原生 macOS 菜单栏 CLI Agent 监控工具（**仅支持 [Rex](https://www.superlogical.com/) 终端**），实时检测在 **[Rex](https://www.superlogical.com/)** 中运行的 **Claude Code**、**Codex CLI**、**Copilot CLI** 与 **Antigravity CLI** 会话状态，让你无需离开当前工作窗口即可在菜单栏掌控所有 Agent。

## 为什么使用 Agent Meter？

- **告别「保姆式盯梢」与权限卡死**：当后台 Agent 停在 `y/n` 等待权限确认时，菜单栏图标立即亮起琥珀色提醒；无需切换窗口，直接在菜单栏点击 **`允许 ⏎`** 或 **`拒绝 Esc`** 原地放行。
- **不再来回翻找终端与 Tab**：集中预览本机与远程 SSH 会话的最新终端输出，按 **`⌥ + Return`**（或点击任意卡片）即可一键精准跳转到对应的 **[Rex](https://www.superlogical.com/)** 窗口与 Tab。
- **Git 变更微章（`+N -M`）、5 分钟热缓存倒计时与 Context 预警**：卡片实时展示代码增删行数（`+142 -28`）、5 分钟 Prompt Cache 保温倒计时（`🔥 4:42`）以及 5 段式上下文容量指示（`64%`）。
- **本地目录与远程 SSH 一键启动（`+`）**：自动汇总常用本地工作目录与远程 SSH 机器（解析 `~/.ssh/config` 与活跃 SSH 会话），每个工作区下方直接提供 **`Codex`**、**`Claude`**、**`Copilot`**、**`Antigravity`** 四个按钮，一键连接并在 **Rex** 中启动对应 Agent。
- **历史会话搜索、一键恢复与安全物理删除**：检索本机所有历史会话并在 **Rex** 中一键恢复上下文，或通过两步确认安全清理本地历史数据。

## 全局与面板快捷键

| 快捷键 | 功能说明 |
| :--- | :--- |
| `⌥ + Space`（`Option + Space`） | 唤起或收起 Agent Meter 菜单栏面板 |
| `⌥ + Return`（`Option + Return`） | 一键直接跳转到当前最紧急的 Rex Agent 会话 |
| `↑` / `↓` | 在面板列表中上下移动选择会话卡片（或目录 / 历史记录项） |
| `←` / `→` | 在 `全部` / `活跃` / `完成` 筛选标签之间左右切换（或在新建/历史页切换 Agent 筛选） |
| `Return ⏎` | 若选中项为 `待确认` 则直接授权放行，否则一键跳转到对应的 Rex 终端窗口 |
| `/` | 唤起并聚焦当前选中会话的内联快捷回复框（在历史页则聚焦搜索框） |
| `Esc` | 退出输入框焦点 / 返回上一级视图，或收起面板 |

*（可在面板设置中随时开启或关闭全局快捷键。）*

## 环境要求

- macOS 14.0+
- **[Rex](https://www.superlogical.com/)** 终端（仅支持 Rex，不支持其他终端应用）
- Swift 6.0+（Xcode Command Line Tools）

## 编译与运行

使用打包脚本构建 `.app` 应用包并运行：

```sh
zsh scripts/build-app.sh
open "build/Agent Meter.app" --args --show-panel
```

也可以直接使用 Swift Package Manager 编译：

```sh
swift build -c release
```

演示模式：

```sh
open -n "build/Agent Meter.app" --args --demo --show-panel
```

## 后续计划 / TODO

- [x] **菜单栏内直接快捷回复（Inline Quick Reply `/`）**：支持在面板卡片内直接输入一句话指令或快捷发送常用命令（如 `/compact`、`continue`）至对应的 Rex 终端，无需切换窗口。
- [x] **Prompt Cache 热缓存保温倒计时（`🔥 4:42`）**：针对刚完成或空闲的会话（Claude Code、Codex CLI 等）提供 5 分钟热缓存倒计时提醒，避免闲置超时导致缓存失效（Cache Miss）、响应变慢与额度额外消耗。
- [x] **开机自动启动（Launch at Login）**：支持登录 macOS 时在后台自动启动 Agent Meter。
- [x] **历史会话搜索、一键恢复与物理删除（Historical Session Resume & Delete）**：自动扫描并检索本机 Claude Code、Codex CLI、Copilot CLI 与 Antigravity 的历史会话记录，支持在 Rex 新建 Tab 中一键恢复任意历史对话，或通过两步确认永久删除会话文件。
- [x] **卡片 Git 变更微章（`+64 -22` Dirty Files Badge）**：在会话卡片上实时展示当前工作区的代码增删行数（`+N -M`）与变更文件数，一眼看清每个 Agent 改了多少代码。
- [x] **本地目录与远程 SSH 一键启动（Unified Local & SSH Launch `+`）**：自动汇总常用本地目录与远程 SSH 主机（`~/.ssh/config` 与活跃 SSH 会话），每个工作区下提供 `Codex`、`Claude`、`Copilot`、`Antigravity` 四个一键启动按钮。
- [x] **全键盘快捷导航（Full Keyboard Navigation）**：支持 `↑`/`↓` 选择卡片、工作区或历史记录，`←`/`→` 切换筛选或 Agent，`⏎` 一键放行/跳转/启动，`/` 聚焦内联回复或搜索。

