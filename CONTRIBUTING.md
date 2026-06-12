# Contributing to GlassClip

Thanks for your interest! GlassClip is intentionally small and heavily
commented — it doubles as a learning codebase for Go + native macOS.

## Getting started

1. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (5 minutes).
2. `go test -race ./...` must pass before and after your change.
3. `go vet ./...` and `gofmt` are the only style rules.

## Ground rules

- **Readability over cleverness.** A beginner Go programmer should be
  able to follow any function. If a change needs a comment to be
  understood, write the comment.
- **No new dependencies** without discussion — the Go side is currently
  stdlib-only and we'd like to keep it that way.
- **Keep packages in their lanes:** `history` stays free of I/O and
  macOS; only `clipboard` may touch the pasteboard; protocol changes go
  through `server` and must stay backward compatible (additive fields).
- New logic needs a test. The injection seams (`ReadFunc`,
  `setClipboard`) exist precisely so you can test without a real
  clipboard.

## Good first issues

- Add a `{"cmd":"delete","id":…}` command to remove a single item
- Configurable history size (flag or config file)
- A `glassclip` CLI client for the socket (great nc replacement)

## Submitting

Fork → branch → PR against `main`, with a short description of *why*.
One logical change per PR.
