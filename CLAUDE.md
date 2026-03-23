# AgentFlow

Native macOS app for orchestrating AI agents and terminals on an infinite canvas.

## Architecture

- **Swift 6 / SwiftUI** targeting macOS 26 (Tahoe)
- **Multi-package structure** under `Packages/`:
  - `AFCore` — Domain models (no UI deps)
  - `AFCanvas` — Canvas rendering, state management, persistence
  - `AFAgent` — AI providers (Claude Code, Codex/OpenAI), terminal sessions
  - `AFTerminal`, `AFPersistence`, `AFDiff` — Placeholder packages for future use
- **Main app target** in `AgentFlow/` — Views, commands, services
- **XcodeGen** — `project.yml` generates `AgentFlow.xcodeproj`

## Key Files

- `AgentFlow/AgentFlowApp.swift` — App entry point, single Window scene
- `AgentFlow/Views/ProjectEditorView.swift` — Main editor with canvas, sidebar, providers
- `AgentFlow/Views/AgentNodePanel.swift` — AI agent chat panel (Claude/Codex)
- `AgentFlow/Views/TerminalNodePanel.swift` — Terminal panel with shell sessions
- `Packages/AFAgent/Sources/AFAgent/Providers/ClaudeCodeProvider.swift` — Claude Code CLI integration
- `Packages/AFAgent/Sources/AFAgent/Providers/CodexProvider.swift` — Codex app-server JSON-RPC
- `Packages/AFCanvas/Sources/AFCanvas/ProjectPersistence.swift` — Save/load projects

## Providers

### Claude Code
- Spawns `claude -p --output-format stream-json --dangerously-skip-permissions`
- Token-by-token streaming via `--include-partial-messages`
- Session resume via `--resume <sessionID>`
- Binary found at `~/.local/bin/claude`

### Codex (OpenAI)
- Persistent `codex app-server` process via JSON-RPC over stdio
- Protocol: `initialize` → `thread/start` → `turn/start` per message
- Sandbox: `danger-full-access`, approval: `never`
- Thread reused across messages for context continuity

## Persistence

- Projects: `~/Library/Application Support/AgentFlow/projects.json`
- Conversations: `~/Library/Application Support/AgentFlow/conversations/<projectID>.json`
- Backup: `projects.backup.json` created before each save

## Build

```bash
# Generate Xcode project
xcodegen generate

# Build from CLI
xcodebuild -project AgentFlow.xcodeproj -scheme AgentFlow -configuration Release build

# Build app bundle
xcodebuild -project AgentFlow.xcodeproj -scheme AgentFlow -configuration Release -derivedDataPath build archive -archivePath build/AgentFlow.xcarchive

# Run tests
cd Packages/AFCore && swift test
cd Packages/AFCanvas && swift test
cd Packages/AFAgent && swift test
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+N | New project (folder picker) |
| Cmd+K | Command palette |
| Cmd+B | Toggle sidebar |
| Cmd+D | Duplicate selected node |
| Cmd+Plus/Minus | Zoom in/out |
| Cmd+0 | Reset zoom |
| Delete | Delete selected node |
| Drag empty canvas | Pan canvas |
| Cmd+Drag | Pan canvas (anywhere) |
| Shift+Drag | Snap to grid |

## Conventions

- `@Observable` classes for state (not ObservableObject)
- `nonisolated(unsafe)` for shared mutable state in NSEvent handlers
- Node positions are center-based (x,y = center, width/height = size)
- Canvas coordinate system: `screenPoint = canvasPoint * zoom + offset`
- All saves go through `ProjectPersistence.save()` with backup + guard
