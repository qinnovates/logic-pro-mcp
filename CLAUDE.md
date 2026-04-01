# Logic Pro MCP

## Build Commands

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run tests
```

## Architecture

MCP server controlling Logic Pro through 5 macOS communication channels with automatic fallback routing.

- **Executable:** `Sources/LogicProMCP/main.swift` — CLI entry point
- **Library:** `Sources/LogicProMCPLib/` — all business logic
- **Tests:** `Tests/LogicProMCPTests/` — unit tests (5 suites)

### Key Modules

| Module | Path | Responsibility |
|--------|------|----------------|
| Server | `Server/LogicProServer.swift` | MCP tool/resource registration and handling |
| Channels | `Channels/` | 5 channel implementations (CoreMIDI, CGEvent, Accessibility, AppleScript, OSC) |
| Router | `Channels/ChannelRouter.swift` | Fallback routing with circuit breaker |
| State | `State/` | Actor-based cache, state models, background poller |
| MIDI | `MIDI/` | CoreMIDI engine, MIDI feedback, MMC commands |
| Audio | `Audio/` | FFT-based audio analysis, bounce controller |
| Resources | `Resources/` | MCP resource definitions and handlers |

### Channel Router Fallback Order

```
transport → CoreMIDI → CGEvent → Accessibility
track     → Accessibility → CGEvent
mixer     → OSC → Accessibility
midi      → CoreMIDI
edit      → CGEvent
navigate  → CGEvent → Accessibility
project   → AppleScript → CGEvent
```

## Rules

- macOS 14+ only (uses modern Swift concurrency, actor isolation)
- All state management through `StateCache` actor — no mutable shared state
- Channels conform to `Channel` protocol — add new channels there
- Circuit breaker in `ChannelRouter` protects against cascading failures
- Keybindings loaded from bundled `Config/keybindings.json`
- MCP SDK: `modelcontextprotocol/swift-sdk` 0.12+
