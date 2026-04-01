# Logic Pro MCP

## Build Commands

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run tests (112 tests, 9 suites)
```

## Architecture

MCP server controlling Logic Pro through 6 macOS communication channels with automatic fallback routing. Exposes 12 tools, 9 resources, and 3 prompts via the MCP protocol.

- **Executable:** `Sources/LogicProMCP/main.swift` — CLI entry point
- **Library:** `Sources/LogicProMCPLib/` — all business logic
- **Tests:** `Tests/LogicProMCPTests/` — unit tests (9 suites)

### Key Modules

| Module | Path | Responsibility |
|--------|------|----------------|
| Server | `Server/LogicProServer.swift` | MCP server lifecycle, tool/resource/prompt/completion/logging registration |
| Server | `Server/ToolHandlers.swift` + `ToolHandlersV2.swift` | Tool dispatch (transport/track/mixer/MIDI/edit/navigate/project/system + audio/plugin/automation/midi_edit) |
| Server | `Server/ToolDefinitions.swift` + `ToolDefinitionsV2.swift` | Tool JSON Schema definitions |
| Server | `Server/PromptHandlers.swift` | 3 prompts: mix-check, master-for-platform, session-overview |
| Server | `Server/CompletionHandlers.swift` | Auto-complete for prompt args and resource URIs |
| Server | `Server/MCPLogger.swift` | Structured MCP logging with level filtering |
| Server | `Server/InputSanitizer.swift` | Name/path sanitization for AppleScript injection prevention |
| Channels | `Channels/` | 6 channel implementations (CoreMIDI, CGEvent, Accessibility, AppleScript, OSC, Scripter) |
| Router | `Channels/ChannelRouter.swift` | Fallback routing with circuit breaker |
| Scripter | `Scripter/ScripterProtocol.swift` | CC/SysEx bidirectional protocol with 7-bit encoding |
| Scripter | `Scripter/BridgeScript.swift` | JS generator for Logic Pro's Scripter MIDI FX plugin |
| State | `State/StateModels.swift` | 20 Codable+Sendable types (transport, tracks, mixer, plugins, automation, regions, etc.) |
| State | `State/StateCache.swift` + `StatePoller.swift` | Actor-based cache with TTL, adaptive polling |
| MIDI | `MIDI/` | CoreMIDI engine, MIDI feedback, MMC commands |
| Audio | `Audio/AudioAnalyzer.swift` | FFT spectral analysis, RMS, peak |
| Audio | `Audio/LoudnessAnalyzer.swift` | LUFS (EBU R128 approx), true peak (4x cubic Hermite) |
| Audio | `Audio/BounceController.swift` | Audio export/bounce |
| Plugins | `Plugins/PluginDiscovery.swift` | AU plugin enumeration via AVAudioUnitComponentManager |
| Resources | `Resources/` | MCP resource definitions (ResourceProvider) and handlers (ResourceHandlers) |

### Tools (12)

| Tool | Actions |
|------|---------|
| `transport` | play, stop, record, pause, rewind, forward, set_bpm, set_position, toggle_cycle, toggle_metronome |
| `track` | create, delete, rename, select, mute, solo, arm |
| `mixer` | set_volume, set_pan, set_mute |
| `midi_send` | note, cc, program_change, pitch_bend |
| `edit` | undo, redo, quantize, split, join, copy, paste, delete |
| `navigate` | goto_bar, goto_marker, create_marker, zoom_in, zoom_out, show_mixer, show_editor, show_automation |
| `project` | new, open, save, close, bounce |
| `system` | health, permissions |
| `audio_analyze` | Analyze audio file (LUFS, true peak, RMS, spectral) |
| `plugin` | list_available, insert, remove, get_params, set_param, load_preset, list_presets |
| `automation` | get_mode, set_mode, add_point, get_points, clear, list_parameters |
| `midi_edit` | list_regions, get_notes, add_note, delete_note, move_note, set_velocity, quantize |

### Channel Router Fallback Order

```
transport  → CoreMIDI → Scripter → CGEvent → Accessibility
track      → Accessibility → CGEvent
mixer      → OSC → Accessibility
midi       → CoreMIDI
edit       → CGEvent
navigate   → CGEvent → Accessibility
project    → AppleScript → CGEvent
plugin     → Accessibility → CGEvent → AppleScript
automation → Accessibility → CGEvent
midi_edit  → Scripter → Accessibility → CGEvent
```

### MCP Protocol Features

| Feature | Status |
|---------|--------|
| Tools | 12 tools with JSON Schema input validation |
| Resources | 9 resources (transport, tracks, mixer, project, health, MIDI ports, audio analysis, track detail, available plugins) |
| Prompts | 3 prompts (mix-check, master-for-platform, session-overview) |
| Completions | Auto-suggest for prompt args + resource URIs |
| Logging | Structured MCP logging with SetLoggingLevel |
| Subscriptions | Declared (subscribe: true) |

## Rules

- macOS 14+ only (uses modern Swift concurrency, actor isolation)
- All state management through `StateCache` actor — no mutable shared state
- Channels conform to `Channel` protocol — add new channels there
- Circuit breaker in `ChannelRouter` protects against cascading failures
- User-supplied names (plugin, preset, param) MUST go through `InputSanitizer.sanitizeName()` before reaching channels
- File paths MUST be validated (absolute, no `..`, no null bytes) before any read/write
- Resource listing uses `ResourceProvider.allResources()`, reading uses `ResourceHandlers.handleRead()` — never inline
- Destructive operations are audit-logged via MCPLogger before execution
- Keybindings loaded from bundled `Config/keybindings.json`
- MCP SDK: `modelcontextprotocol/swift-sdk` .upToNextMinor(from: "0.12.0")
