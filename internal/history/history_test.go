package history

// Run these with:  go test ./...
// Test files end in _test.go and are excluded from normal builds.

import (
	"fmt"
	"strings"
	"sync"
	"testing"
)

func TestAddPutsNewestFirst(t *testing.T) {
	h := New(10)
	h.Add(NewItem("first", false))
	h.Add(NewItem("second", false))

	items := h.All()
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(items))
	}
	if items[0].Content != "second" {
		t.Errorf("expected newest item first, got %q", items[0].Content)
	}
}

func TestCapDropsOldest(t *testing.T) {
	h := New(10)
	for i := 1; i <= 11; i++ {
		h.Add(NewItem(fmt.Sprintf("item %d", i), false))
	}

	items := h.All()
	if len(items) != 10 {
		t.Fatalf("expected 10 items after cap, got %d", len(items))
	}
	if items[0].Content != "item 11" {
		t.Errorf("expected newest to be 'item 11', got %q", items[0].Content)
	}
	// "item 1" was the oldest, so it should be gone.
	for _, it := range items {
		if it.Content == "item 1" {
			t.Error("oldest item should have been dropped")
		}
	}
}

func TestDuplicateMovesToFront(t *testing.T) {
	h := New(10)
	h.Add(NewItem("hello", false))
	h.Add(NewItem("world", false))
	h.Add(NewItem("hello", false)) // copy "hello" again

	items := h.All()
	if len(items) != 2 {
		t.Fatalf("duplicate should not grow the list: got %d items", len(items))
	}
	if items[0].Content != "hello" {
		t.Errorf("duplicate should move to front, got %q first", items[0].Content)
	}
}

func TestGetByID(t *testing.T) {
	h := New(10)
	item := NewItem("findme", false)
	h.Add(item)

	got, ok := h.Get(item.ID)
	if !ok {
		t.Fatal("expected to find item by ID")
	}
	if got.Content != "findme" {
		t.Errorf("got wrong item: %q", got.Content)
	}

	if _, ok := h.Get("nonexistent"); ok {
		t.Error("expected miss for unknown ID")
	}
}

func TestURLDetection(t *testing.T) {
	cases := map[string]ItemType{
		"https://github.com/sathvik458": TypeURL,
		"http://example.com":            TypeURL,
		"just some text":                TypeText,
		"https://a.com and more words":  TypeText, // sentence containing a URL is still text
		"ftp://example.com":             TypeText, // only http(s) counts
	}
	for content, want := range cases {
		if got := NewItem(content, false).Type; got != want {
			t.Errorf("NewItem(%q).Type = %q, want %q", content, got, want)
		}
	}
}

func TestPreviewTruncation(t *testing.T) {
	long := strings.Repeat("a", 200)
	item := NewItem(long, false)
	if len([]rune(item.Preview)) > 121 { // 120 chars + "…"
		t.Errorf("preview too long: %d runes", len([]rune(item.Preview)))
	}
	if !strings.HasSuffix(item.Preview, "…") {
		t.Error("truncated preview should end with …")
	}

	fourLines := "one\ntwo\nthree\nfour"
	item = NewItem(fourLines, false)
	if strings.Count(item.Preview, "\n") > 2 {
		t.Errorf("preview should have at most 3 lines, got %q", item.Preview)
	}
}

// TestConcurrentAccess hammers the history from many goroutines at once.
// Run with the race detector (go test -race ./...) to prove the mutex
// actually protects us.
func TestConcurrentAccess(t *testing.T) {
	h := New(10)
	var wg sync.WaitGroup

	for i := 0; i < 50; i++ {
		wg.Add(2)
		go func(n int) {
			defer wg.Done()
			h.Add(NewItem(fmt.Sprintf("writer %d", n), false))
		}(i)
		go func() {
			defer wg.Done()
			_ = h.All()
		}()
	}
	wg.Wait()

	if h.Len() > 10 {
		t.Errorf("cap violated under concurrency: %d items", h.Len())
	}
}
