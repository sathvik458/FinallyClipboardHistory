# GlassClip

A clipboard history manager for macOS, inspired by Windows 11's Win+V —
rebuilt with Apple-style glassmorphism. Press **⌘⇧V**, see your last 10
copies in a frosted floating panel, pick one, and it pastes.

Built as a learning project: **Go** for all the logic, **SwiftUI/AppKit**
for the native UI.

## Why Go + SwiftUI (and not Wails)?

| Priority | Winner | Why |
|---|---|---|
| Native macOS look | SwiftUI | Real `NSVisualEffectView` blur, vibrancy materials, `NSPanel`. Wails renders HTML in a WebView — CSS blur is fake and never matches Control Center. |
| Simplicity | Go + thin Swift | Go owns *all* decisions (what to store, dedupe, persistence). Swift only draws pixels and forwards keystrokes. Each side stays small. |
| Performance | Both | Go daemon idles at ~0% CPU; native panel animates at 120 Hz. |

The two halves talk over a **Unix domain socket** with line-delimited JSON.
Think of it as a tiny local web API you can poke with `nc -U`.

## Architecture & data flow

```
 You press ⌘C                              You press ⌘⇧V
      │                                         │
      ▼                                         ▼
 macOS Pasteboard ◄─────── paste ─────── SwiftUI popup (NSPanel + blur)
      │  changeCount polling                    │ {"cmd":"history"}
      ▼                                         │ {"cmd":"select","id":…}
 ┌─ Go daemon (glassclipd) ─────────────────────▼─────────┐
 │  internal/clipboard  ──► internal/history ◄── internal/server │
 │   (monitor goroutine)     (mutex-guarded,      (unix socket,  │
 │                            max 10, deduped)     JSON API)     │
 │                              │                                │
 │                              ▼ internal/storage (Phase 5)     │
 │            ~/Library/Application Support/GlassClip/history.json
 └───────────────────────────────────────────────────────────────┘
```

Two goroutines run concurrently in the daemon: the **monitor** (writes new
items) and the **server** (reads items for the UI). `history.History`
guards its slice with a `sync.Mutex` so they never race.

## Folder structure

```
glassclip/
├── cmd/glassclipd/      main() for the Go daemon — Go convention: one
│                        folder per binary under cmd/
├── internal/            private packages; the Go compiler forbids other
│   │                    modules from importing anything under internal/
│   ├── history/         data model + last-10 ring (pure logic, no macOS)
│   ├── clipboard/       pasteboard watcher (Phase 2)
│   ├── server/          unix-socket JSON API (Phase 2)
│   └── storage/         JSON persistence (Phase 5)
└── ui/GlassClip/        SwiftUI app: panel, hotkey, paste (Phases 3–4)
```

No `pkg/` folder: that's for code other projects import. We have none, so
idiomatic modern Go skips it.

## Data model

**`ClipboardItem`** — ID (unique handle so the UI can request a paste
without resending content), Type (`text`/`url`/`rich`, with `image`
reserved), Content (full text, what gets pasted), Preview (pre-trimmed
3-line/120-char string computed in Go so Swift stays dumb), Timestamp.

**`History`** — maxItems (10), items (newest first), and a mutex. Adding a
duplicate moves the existing entry to the front instead of storing twice;
item #11 evicts the oldest.

## Implementation plan

- [x] **Phase 1** — module, data model, history ring, unit tests
- [ ] **Phase 2** — clipboard monitor + unix-socket server (Go daemon complete)
- [ ] **Phase 3** — SwiftUI glassmorphism popup with keyboard navigation
- [ ] **Phase 4** — global ⌘⇧V hotkey, paste injection, daemon lifecycle
- [ ] **Phase 5** — JSON persistence, packaging, docs polish

## Building & testing (so far)

```sh
go test -race ./...   # run unit tests with the race detector
go vet ./...          # static checks
```

Full app build instructions arrive with Phase 5.

## macOS permissions (needed from Phase 4)

- **Accessibility** (System Settings → Privacy & Security): required to
  send the synthetic ⌘V keystroke that performs the paste.
- No other permissions: clipboard reading needs none, and everything stays
  on-device.

## Future features the architecture leaves room for

Search, pinned favorites, images/OCR, iCloud sync, tagging, AI
categorization, quick actions, analytics. They all hang off the same two
seams: new `ItemType`s in `internal/history`, and new commands in the
socket protocol (`internal/server`).
