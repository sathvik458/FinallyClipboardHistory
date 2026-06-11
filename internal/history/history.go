package history

import "sync"

// DefaultMaxItems is how many clipboard entries we keep, matching the
// Windows 11 clipboard history feel.
const DefaultMaxItems = 10

// History is the in-memory list of recent clipboard items.
//
// Why these fields exist:
//   - maxItems: the cap. When item #11 arrives, the oldest is dropped.
//   - items:    the entries, NEWEST FIRST (index 0 = most recent copy),
//               because that is the order the popup displays them in.
//   - mu:       a mutex (lock). Two goroutines touch this struct at the
//               same time: the clipboard monitor ADDS items while the
//               socket server READS them for the UI. Without the lock,
//               that is a data race (undefined behavior in Go). Every
//               public method locks on entry and unlocks on exit.
//
// The fields are lowercase (unexported) on purpose: outside code must go
// through the methods, which guarantees the lock is always taken.
type History struct {
	mu       sync.Mutex
	maxItems int
	items    []ClipboardItem
}

// New creates an empty history that holds at most maxItems entries.
func New(maxItems int) *History {
	if maxItems <= 0 {
		maxItems = DefaultMaxItems
	}
	return &History{maxItems: maxItems}
}

// Add puts an item at the front of the list (newest first).
//
// Duplicate handling: if the same content is already in the list (e.g. you
// copied the same text twice), we don't store it again — we just move the
// existing entry to the front. This is what Windows 11 does too.
func (h *History) Add(item ClipboardItem) {
	h.mu.Lock()
	defer h.mu.Unlock() // defer = "run this when the function returns"

	// Remove any existing entry with the same content first.
	for i, existing := range h.items {
		if existing.Content == item.Content && existing.Type == item.Type {
			// append(a[:i], a[i+1:]...) is the standard Go idiom for
			// "delete element i from a slice".
			h.items = append(h.items[:i], h.items[i+1:]...)
			break
		}
	}

	// Put the new item at the front.
	h.items = append([]ClipboardItem{item}, h.items...)

	// Enforce the cap: drop the oldest (last) entries.
	if len(h.items) > h.maxItems {
		h.items = h.items[:h.maxItems]
	}
}

// All returns a COPY of the items, newest first.
// We copy so the caller can't accidentally modify our internal slice
// after the lock has been released.
func (h *History) All() []ClipboardItem {
	h.mu.Lock()
	defer h.mu.Unlock()

	out := make([]ClipboardItem, len(h.items))
	copy(out, h.items)
	return out
}

// Get looks up one item by its ID. The second return value follows Go's
// "comma ok" convention: false means not found.
func (h *History) Get(id string) (ClipboardItem, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()

	for _, item := range h.items {
		if item.ID == id {
			return item, true
		}
	}
	return ClipboardItem{}, false
}

// Len reports how many items are stored.
func (h *History) Len() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.items)
}

// Clear removes everything.
func (h *History) Clear() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.items = nil
}

// Replace swaps in a whole list at once. The storage package (Phase 5)
// uses this to restore history from disk at startup.
func (h *History) Replace(items []ClipboardItem) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if len(items) > h.maxItems {
		items = items[:h.maxItems]
	}
	h.items = make([]ClipboardItem, len(items))
	copy(h.items, items)
}
