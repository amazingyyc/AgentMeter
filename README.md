<p align="center">
  <img src="./Resources/AppIcon.png" width="112" height="112" alt="Agent Meter Logo" />
</p>

<h1 align="center">Agent Meter</h1>

<p align="center">
  English | <a href="./README_zh.md">简体中文</a>
</p>

<p align="center">
  <img src="./Resources/demo.webp" width="100%" alt="Agent Meter Interactive Demo" />
</p>

A native macOS menu bar CLI Agent monitor (**[Rex](https://www.superlogical.com/) terminal only**). It detects active **Claude Code**, **Codex CLI**, **Copilot CLI**, and **Antigravity CLI** sessions running inside **[Rex](https://www.superlogical.com/)** in real time, letting you manage all agents from the menu bar without breaking your coding flow.

## Why Agent Meter?

- **Stop Babysitting `y/n` Prompts**: Get an instant amber menu bar alert the moment an agent pauses for permission, and click **`Allow ⏎`** or **`Deny Esc`** inline without leaving your current window.
- **No More Tab Hunting**: Preview the latest terminal output of all local and SSH sessions in one place, and press **`⌥ + Return`** (or click any card) to jump straight to the exact **Rex** window and tab.
- **Prevent Mid-Task Context Compaction**: Monitor each session's 5-segment context window usage meter (`%`) at a glance before auto-compaction catches you off guard.
- **1-Click Session Launch & History Resume**: Start a new Claude, Codex, Copilot, or Antigravity session in any recent workspace directory, or browse and search all historical sessions to resume them in **Rex** with a single click.

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌥ + Space` (`Option + Space`) | Toggle Agent Meter menu bar panel |
| `⌥ + Return` (`Option + Return`) | Jump straight to the #1 most urgent Rex agent session |

*(Global shortcuts can be enabled or disabled in Settings.)*

## Requirements

- macOS 14.0+
- **[Rex](https://www.superlogical.com/)** terminal (Rex only; other terminal emulators are not supported)
- Swift 6.0+ (Xcode Command Line Tools)

## Build & Run

Build the `.app` bundle and open it:

```sh
zsh scripts/build-app.sh
open "build/Agent Meter.app" --args --show-panel
```

Or build directly with Swift Package Manager:

```sh
swift build -c release
```

Demo mode:

```sh
open -n "build/Agent Meter.app" --args --demo --show-panel
```

## Roadmap / TODO

- [x] **Inline Quick Reply**: Send short follow-up prompts or slash commands (e.g., `/compact`, `continue`) directly from the menu bar popover to the target Rex session without switching windows.
- [x] **Prompt Cache Warm Timer**: Display a 5-minute warm cache countdown on newly completed/idle sessions (Claude Code, Codex CLI, etc.) so you can follow up before prompt cache eviction causes slow TTFT and costly token re-prefills.
- [x] **Launch at Login**: Automatically start Agent Meter in the background when logging into macOS.
- [x] **Historical Session Resume**: Browse, filter, and search local historical sessions across Claude Code, Codex CLI, Copilot CLI, and Antigravity, and resume any conversation in a new Rex tab with one click.
- [x] **Git Diff Stat Badge (`+64 -22`)**: Display live working-tree line additions and deletions on each session card so you can see how much code an agent has modified at a glance.

