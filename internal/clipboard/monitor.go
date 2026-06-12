// Package clipboard talks to the macOS pasteboard and watches it for
// changes. It is the only Go package that knows it's running on a Mac.
//
// How it reads the clipboard: by running the built-in `pbpaste` command
// and capturing its output. Writing uses `pbcopy`. Shelling out to tiny
// system tools keeps this pure Go — no cgo, no Objective-C — at the cost
// of spawning a short-lived process per poll.
//
// Tradeoff worth knowing (and a good interview answer): macOS has no
// push notification for clipboard changes. Even native Swift apps poll
// NSPasteboard.changeCount on a timer. The "proper" optimization would be
// cgo calling changeCount (an integer compare instead of reading content),
// but that drags in a C toolchain and makes the code much harder to read.
// At 2 polls/second, pbpaste keeps CPU usage near 0% — simplicity wins.
package clipboard

import (
	"context"
	"os/exec"
	"strings"
	"time"

	"github.com/sathvik458/glassclip/internal/history"
)

// DefaultInterval is how often we check the clipboard. 500ms feels
// instant to a human (you can't copy and press ⌘⇧V faster than that)
// while keeping the daemon essentially idle.
const DefaultInterval = 500 * time.Millisecond

// maxContentSize ignores absurdly large copies (e.g. a whole log file).
// 1 MB of text is ~500 pages — plenty for a history tool.
const maxContentSize = 1 << 20

// ReadFunc abstracts "read the clipboard" behind a function type.
//
// Why: in production we use readWithPbpaste below, but in unit tests we
// swap in a fake that returns canned strings. This is dependency
// injection, Go style — no frameworks, just a function value.
type ReadFunc func() (string, error)

// readWithPbpaste is the real clipboard reader. exec.Command runs
// /usr/bin/pbpaste and .Output() captures its stdout.
func readWithPbpaste() (string, error) {
	out, err := exec.Command("pbpaste").Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// SetText writes a string to the macOS clipboard via pbcopy.
// The server calls this when the user picks an item to paste.
func SetText(content string) error {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(content) // pbcopy reads from stdin
	return cmd.Run()
}

// Monitor polls the clipboard and feeds new content into the history.
//
// Why these fields exist:
//   - history:  where new items go.
//   - read:     the injected clipboard reader (see ReadFunc).
//   - interval: poll frequency.
//   - last:     the previous clipboard content. Comparing against it is
//               how we detect "something new was copied" and how we avoid
//               re-adding the same content on every tick. Only the
//               monitor goroutine touches this field, so it needs no lock.
type Monitor struct {
	history  *history.History
	read     ReadFunc
	interval time.Duration
	last     string
}

// NewMonitor creates a monitor wired to the real pbpaste reader.
func NewMonitor(h *history.History) *Monitor {
	return &Monitor{
		history:  h,
		read:     readWithPbpaste,
		interval: DefaultInterval,
	}
}

// Run polls until ctx is cancelled. Call it in its own goroutine:
//
//	go monitor.Run(ctx)
//
// Concurrency notes:
//   - time.Ticker fires on a channel every interval. Using a ticker
//     instead of time.Sleep in a loop means cancellation is instant:
//     select waits on BOTH channels and acts on whichever is ready first.
//   - ctx.Done() is closed when main() decides to shut down (Ctrl-C).
//     This is the standard Go pattern for stopping a background goroutine.
func (m *Monitor) Run(ctx context.Context) {
	ticker := time.NewTicker(m.interval)
	defer ticker.Stop() // free the ticker's resources when Run exits

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.poll()
		}
	}
}

// poll does one clipboard check. Kept as its own method so tests can
// call it directly without spinning up the ticker loop.
func (m *Monitor) poll() {
	content, err := m.read()
	if err != nil {
		// Clipboard read failed (rare). Skip this tick rather than
		// crash; we'll try again in half a second.
		return
	}

	// Ignore: empty clipboard, unchanged content, or huge payloads.
	if content == "" || content == m.last || len(content) > maxContentSize {
		return
	}

	m.last = content
	m.history.Add(history.NewItem(content, false))
}
