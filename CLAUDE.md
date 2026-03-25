# Flow

Native macOS app for orchestrating AI agents and terminals on an infinite canvas.

## Architecture

- **Swift 6 / SwiftUI** targeting macOS 26 (Tahoe)
- **Multi-package structure** under `Packages/`:
  - `AFCore` — Domain models (no UI deps)
  - `AFCanvas` — Canvas rendering, state management, persistence
  - `AFAgent` — AI providers (Claude Code, Codex/OpenAI), terminal sessions
  - `AFTerminal`, `AFPersistence`, `AFDiff` — Placeholder packages for future use
- **Main app target** in `Flow/` — Views, commands, services
- **XcodeGen** — `project.yml` generates `Flow.xcodeproj`

## Build

```bash
make dev       # Debug build + open (dist/Flow-Dev.app)
make build     # Release build (dist/Flow.app)
make test      # Run all package tests
make clean     # Remove build artifacts
```

Debug and Release use different bundle IDs and data directories so they don't interfere with each other.

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

- Debug data: `~/Library/Application Support/Flow-Dev/`
- Release data: `~/Library/Application Support/Flow/`
- Projects: `projects.json`
- Conversations: `conversations/<projectID>.json`
