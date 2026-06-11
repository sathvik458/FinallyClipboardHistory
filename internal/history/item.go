// Package history holds GlassClip's core data model: what a clipboard
// item looks like, and the list that keeps the last N of them.
//
// This package has NO knowledge of macOS, sockets, or files. It is pure
// Go logic, which makes it trivial to unit-test. Everything else in the
// app (the clipboard monitor, the socket server, storage) builds on top
// of it.
package history

import (
	"net/url"
	"strconv"
	"strings"
	"time"
)

// ItemType tells the UI what kind of content an item holds, so it can
// pick the right icon and preview style. It is a string (not an int)
// so that it reads nicely when we serialize items to JSON:
// {"type": "url"} is clearer than {"type": 1}.
type ItemType string

const (
	TypeText ItemType = "text" // plain text
	TypeURL  ItemType = "url"  // a single http(s) link
	TypeRich ItemType = "rich" // rich text (RTF); content is the plain-text version
	// TypeImage is reserved for the future image feature. Defining it now
	// means the rest of the app already has a slot for it.
	TypeImage ItemType = "image"
)

// ClipboardItem is one entry in the history.
//
// Why these fields exist:
//   - ID:        a unique handle so the UI can say "paste item X" without
//                resending the whole content over the socket.
//   - Type:      see ItemType above.
//   - Content:   the full original text. This is what gets pasted.
//   - Preview:   a short, pre-trimmed version for the popup list. We compute
//                it once here in Go so the Swift side stays dumb and simple.
//   - Timestamp: when the item was copied, shown as "2m ago" in the UI.
//
// The `json:"..."` tags control the field names when this struct is
// converted to JSON for the Swift UI. Go uses CapitalizedNames for public
// fields, but JSON conventionally uses lowercase.
type ClipboardItem struct {
	ID        string    `json:"id"`
	Type      ItemType  `json:"type"`
	Content   string    `json:"content"`
	Preview   string    `json:"preview"`
	Timestamp time.Time `json:"timestamp"`
}

// NewItem builds a ClipboardItem from raw clipboard text.
// It fills in everything the caller shouldn't have to think about:
// the ID, the detected type, the preview, and the timestamp.
func NewItem(content string, rich bool) ClipboardItem {
	itemType := TypeText
	if rich {
		itemType = TypeRich
	} else if looksLikeURL(content) {
		itemType = TypeURL
	}

	return ClipboardItem{
		// UnixNano is the current time in nanoseconds. Two copies can't
		// realistically land on the same nanosecond, so it works as a
		// simple unique ID without pulling in a UUID library.
		ID:        strconv.FormatInt(time.Now().UnixNano(), 10),
		Type:      itemType,
		Content:   content,
		Preview:   makePreview(content),
		Timestamp: time.Now(),
	}
}

// looksLikeURL reports whether the copied text is a single web link.
// Rule of thumb: one line, no spaces, parses as http(s) with a host.
func looksLikeURL(s string) bool {
	s = strings.TrimSpace(s)
	if s == "" || strings.ContainsAny(s, " \n\t") {
		return false
	}
	u, err := url.Parse(s)
	if err != nil {
		return false
	}
	return (u.Scheme == "http" || u.Scheme == "https") && u.Host != ""
}

// makePreview trims content down to what the popup actually shows:
// at most 3 lines, at most 120 characters, with "…" when cut off.
func makePreview(content string) string {
	const maxLines = 3
	const maxChars = 120

	preview := strings.TrimSpace(content)
	truncated := false

	lines := strings.Split(preview, "\n")
	if len(lines) > maxLines {
		lines = lines[:maxLines]
		truncated = true
	}
	preview = strings.Join(lines, "\n")

	// Count runes (characters), not bytes, so multi-byte characters
	// like emoji or accented letters are never cut in half.
	runes := []rune(preview)
	if len(runes) > maxChars {
		runes = runes[:maxChars]
		truncated = true
	}
	preview = string(runes)

	if truncated {
		preview += "…"
	}
	return preview
}
