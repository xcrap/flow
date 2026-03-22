# AgentFlow

A native macOS app for orchestrating AI agents and terminals on an infinite canvas. Built with Swift 6 and SwiftUI for macOS 26 (Tahoe).

![AgentFlow](https://img.shields.io/badge/macOS-26+-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![Tests](https://img.shields.io/badge/tests-187%20passing-green)

## Features

- **Infinite Canvas** — Drag, zoom, pan. Place AI agents and terminals anywhere.
- **Claude Code Integration** — Chat with Claude via Claude Code CLI. Full tool use, streaming, session resume.
- **Codex (OpenAI) Integration** — GPT-5.4 via Codex app-server. Persistent threads, full context.
- **Terminal Nodes** — Real shell sessions on the canvas. Run commands, see output.
- **Folder-Based Projects** — Each project maps to a directory. Agents and terminals operate in that folder.
- **Full Persistence** — Projects, nodes, conversations, terminal history, canvas state all survive restarts.
- **Command Palette** — Cmd+K for quick actions.
- **Git Integration** — Branch display, commit, push from toolbar.
- **Code Blocks** — Syntax-highlighted code with copy button.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 16+ (for building)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Claude Code](https://claude.ai/code) CLI installed (`claude` in PATH)
- [Codex](https://openai.com/codex) CLI installed (`codex` in PATH) — optional, for OpenAI models

## Build & Run

### From Xcode

```bash
xcodegen generate
open AgentFlow.xcodeproj
# Cmd+R to build and run
```

### From Command Line

```bash
# Generate project
xcodegen generate

# Build release
xcodebuild -project AgentFlow.xcodeproj \
  -scheme AgentFlow \
  -configuration Release \
  -derivedDataPath build \
  build

# The app bundle is at:
# build/Build/Products/Release/AgentFlow.app

# Run it
open build/Build/Products/Release/AgentFlow.app
```

### Bundle for Distribution

```bash
# Archive
xcodebuild -project AgentFlow.xcodeproj \
  -scheme AgentFlow \
  -configuration Release \
  -derivedDataPath build \
  archive \
  -archivePath build/AgentFlow.xcarchive

# Export app from archive
xcodebuild -exportArchive \
  -archivePath build/AgentFlow.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

### Run Tests

```bash
cd Packages/AFCore && swift test
cd Packages/AFCanvas && swift test
cd Packages/AFAgent && swift test
```

## Quick Start

1. Build and run the app
2. Press **Cmd+N** to create a project (pick a folder)
3. Click **+** in toolbar to add an AI Agent or Terminal
4. Chat with Claude or run commands
5. Drag nodes by their title bar, resize from edges

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+N` | New project |
| `Cmd+K` | Command palette |
| `Cmd+B` | Toggle sidebar |
| `Cmd+D` | Duplicate node |
| `Cmd+Plus` | Zoom in |
| `Cmd+Minus` | Zoom out |
| `Cmd+0` | Reset zoom |
| `Delete` | Delete selected |
| `Option+Drag` | Pan canvas |
| `Shift+Drag` | Snap to grid |
| Right-click | Rename / Duplicate / Delete node |

## Tech Stack

- **SwiftUI** — All UI
- **Swift 6** — Strict concurrency
- **XcodeGen** — Project generation
- **Claude Code CLI** — AI agent backend
- **Codex CLI** — OpenAI agent backend (app-server JSON-RPC)

## License

MIT
