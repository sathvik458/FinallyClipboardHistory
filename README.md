# GlassClip

**Clipboard history for macOS, the way it should look.**

Press **⌘⇧V** and a frosted glass panel floats up with your last 10
copies — text, links, rich text. Arrow down, hit Enter, and it pastes.
Windows 11's Win+V, rebuilt with real macOS materials.

> Status: 🚧 under active development. The Go daemon works; the SwiftUI
> panel is landing next.

## Features

- 📋 Remembers your last **10** clipboard items automatically
- 🔍 Smart previews — URLs, multi-line text trimmed to 3 lines
- 🪟 Native glassmorphism: `NSVisualEffectView`, vibrancy, soft shadows — no fake CSS blur
- ⌨️ Spotlight-style keyboard navigation: ↑ ↓ Enter Esc
- 🔁 Duplicate copies move to the top instead of cluttering the list
- 🔒 100% on-device. No network, no analytics, history stored under your user account only

## How it works

GlassClip is two small programs:

```
┌─────────────────────┐  unix socket   ┌──────────────────────┐
│ glassclipd (Go)     │◄──────────────►│ GlassClip.app (Swift) │
│ watches clipboard,  │  JSON lines    │ glass panel, hotkey,  │
│ keeps last 10 items │                │ paste keystroke       │
└─────────────────────┘                └──────────────────────┘
```

The Go daemon owns all the logic; the Swift app only draws pixels and
sends keystrokes. Full details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Quick start (current state)

Requires macOS and Go 1.24+ (`brew install go`).

```sh
git clone https://github.com/sathvik458/FinallyClipboardHistory.git
cd FinallyClipboardHistory
go run ./cmd/glassclipd
```

Now copy some text anywhere, then in another terminal:

```sh
echo '{"cmd":"history"}' | nc -U ~/Library/"Application Support"/GlassClip/glassclipd.sock
```

You'll get your clipboard history back as JSON. The GUI arrives in Phase 3.

## Development

```sh
go test -race ./...   # unit tests + race detector
go vet ./...          # static analysis
```

Want to help? See [CONTRIBUTING.md](CONTRIBUTING.md) — the codebase is
deliberately small and heavily commented.

## Roadmap

- [x] History engine (10 items, dedupe, previews)
- [x] Clipboard monitor + unix-socket API
- [ ] SwiftUI glass panel with keyboard navigation
- [ ] Global ⌘⇧V hotkey + paste injection
- [ ] Persistence across restarts
- [ ] Later: search, pinned items, images & OCR, iCloud sync

## License

GPL-3.0 — see [LICENSE](LICENSE).
