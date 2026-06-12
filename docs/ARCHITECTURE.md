# GlassClip Architecture

This document is for contributors who want to understand how the pieces
fit before touching code.

## The two-process design

| Process | Language | Responsibility |
|---|---|---|
| `glassclipd` | Go | Watch clipboard, store last 10 items, dedupe, persist, serve API |
| `GlassClip.app` | Swift/SwiftUI | Glass panel UI, global hotkey, paste keystroke |

Why split? macOS-native visuals (`NSVisualEffectView`, `NSPanel`,
vibrancy) are only reachable from Swift, while we want the logic in Go.
The seam between them is a Unix domain socket — file-permission-secured,
no ports, no firewall prompts.

## Data flow

```
 ⌘C anywhere                                ⌘⇧V
     │                                       │
     ▼                                       ▼
 macOS Pasteboard ◄── pbcopy ──┐      GlassClip.app
     │ pbpaste (500ms poll)    │             │ {"cmd":"history"}
     ▼                         │             │ {"cmd":"select","id":…}
 clipboard.Monitor             │             ▼
     │ Add()                   │      server.Server  (one goroutine
     ▼                         │             │         per connection)
 history.History ◄── All()/Get()─────────────┘
 (mutex, max 10, newest first)
     │
     ▼
 storage (Phase 5): ~/Library/Application Support/GlassClip/history.json
```

## Package map

```
cmd/glassclipd/      main(): wiring, app dir, signals, shutdown
internal/history/    pure data model — no macOS, no I/O, fully unit-tested
internal/clipboard/  pbpaste/pbcopy + polling monitor (the only macOS-aware Go)
internal/server/     unix socket, line-delimited JSON protocol
internal/storage/    (Phase 5) JSON persistence
ui/GlassClip/        the Swift app
```

Dependency rule: everything may import `history`; `history` imports
nothing of ours. `clipboard` and `server` don't know about each other —
`cmd/glassclipd` wires them through the shared `History`.

## Concurrency model

Exactly two long-lived goroutines plus one per client connection:

1. **Monitor** (`clipboard.Monitor.Run`) — ticker loop, writes to History.
2. **Accept loop** (`server.ListenAndServe`) — blocks in Accept, spawns a
   goroutine per connection; those read from History.

`history.History` is the single shared object, guarded by a `sync.Mutex`.
All its fields are unexported so the lock cannot be bypassed. Shutdown is
a `signal.NotifyContext` context cancelled by SIGINT/SIGTERM; the monitor
selects on `ctx.Done()`, and a helper goroutine closes the listener to
unblock Accept.

## The socket protocol

One JSON object per line, both directions. Socket path:
`~/Library/Application Support/GlassClip/glassclipd.sock`.

| Request | Response |
|---|---|
| `{"cmd":"ping"}` | `{"ok":true}` |
| `{"cmd":"history"}` | `{"ok":true,"items":[…]}` (newest first) |
| `{"cmd":"select","id":"…"}` | item copied to clipboard, `{"ok":true}` |
| `{"cmd":"clear"}` | `{"ok":true}` |

Errors: `{"ok":false,"error":"…"}`. Paste flow: UI sends `select`, daemon
pbcopy-s the content, UI hides itself and synthesizes ⌘V into the
previously focused app.

## Design decisions & tradeoffs

- **Polling, not push** — macOS has no clipboard-change notification;
  even native apps poll `NSPasteboard.changeCount`. We poll `pbpaste`
  every 500ms (~0% CPU). A cgo `changeCount` check would be cheaper per
  tick but costs a C toolchain and readability.
- **Previews computed in Go** — the UI gets ready-to-render strings, so
  every future client (CLI? menu bar?) shows identical previews.
- **IDs instead of indexes** — the UI says "paste item 1718…" not "paste
  row 3", so a race with a simultaneous new copy can't paste the wrong item.
- **Dependency injection by function value** — the monitor takes a
  `ReadFunc`, the server takes a `setClipboard func(string) error`. Tests
  swap in fakes; no mocking framework needed.

## Extension points

New content types (images): add an `ItemType`, extend the monitor, give
the UI a new row view. New features (search, pin): new commands in
`server.handle` + methods on `History`. The protocol is additive — old
clients ignore fields they don't know.
