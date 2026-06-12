package clipboard

import (
	"errors"
	"testing"

	"github.com/sathvik458/glassclip/internal/history"
)

// fakeReader returns a controllable ReadFunc — this is why ReadFunc
// exists: tests never touch the real clipboard.
func fakeReader(contents *string, fail *bool) ReadFunc {
	return func() (string, error) {
		if *fail {
			return "", errors.New("simulated pbpaste failure")
		}
		return *contents, nil
	}
}

func newTestMonitor(h *history.History, read ReadFunc) *Monitor {
	return &Monitor{history: h, read: read, interval: DefaultInterval}
}

func TestPollAddsNewContent(t *testing.T) {
	h := history.New(10)
	content := "hello"
	fail := false
	m := newTestMonitor(h, fakeReader(&content, &fail))

	m.poll()
	if h.Len() != 1 {
		t.Fatalf("expected 1 item, got %d", h.Len())
	}

	// Same content again: no new item.
	m.poll()
	if h.Len() != 1 {
		t.Errorf("unchanged clipboard should not add items, got %d", h.Len())
	}

	// New content: one more item.
	content = "world"
	m.poll()
	if h.Len() != 2 {
		t.Errorf("expected 2 items after new content, got %d", h.Len())
	}
}

func TestPollSkipsEmptyAndErrors(t *testing.T) {
	h := history.New(10)
	content := ""
	fail := false
	m := newTestMonitor(h, fakeReader(&content, &fail))

	m.poll() // empty clipboard
	if h.Len() != 0 {
		t.Error("empty clipboard should be ignored")
	}

	fail = true
	content = "won't be seen"
	m.poll() // read error
	if h.Len() != 0 {
		t.Error("read errors should be ignored, not stored")
	}
}

func TestPollSkipsHugeContent(t *testing.T) {
	h := history.New(10)
	content := string(make([]byte, maxContentSize+1))
	fail := false
	m := newTestMonitor(h, fakeReader(&content, &fail))

	m.poll()
	if h.Len() != 0 {
		t.Error("oversized content should be ignored")
	}
}
