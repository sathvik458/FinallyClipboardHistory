package server

// These tests start a real server on a socket in a temp directory and
// talk to it like the Swift UI will.

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/sathvik458/glassclip/internal/history"
)

// startTestServer spins up a server with a fake clipboard and returns
// the socket path plus a pointer to whatever was last "copied".
//
// Gotcha: unix socket paths are capped at ~104 characters on macOS (the
// kernel's sun_path buffer). t.TempDir() embeds the full test name in
// the path, so long test names silently broke Listen. We use our own
// short temp dir under /tmp instead.
func startTestServer(t *testing.T, h *history.History) (string, *string) {
	t.Helper()

	var copied string
	fakeSetClipboard := func(s string) error {
		copied = s
		return nil
	}

	dir, err := os.MkdirTemp("", "gc")
	if err != nil {
		t.Fatalf("temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })

	socketPath := filepath.Join(dir, "s.sock")
	srv := New(h, fakeSetClipboard)

	// Report a Listen failure instead of swallowing it, so the test
	// says WHY the server never came up.
	errCh := make(chan error, 1)
	go func() {
		errCh <- srv.ListenAndServe(socketPath)
	}()
	t.Cleanup(func() { _ = srv.Close() })

	// Wait until the socket accepts connections (the goroutine needs a moment).
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		select {
		case err := <-errCh:
			t.Fatalf("server exited early: %v", err)
		default:
		}
		if conn, err := net.Dial("unix", socketPath); err == nil {
			conn.Close()
			return socketPath, &copied
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("server never started listening")
	return "", nil
}

// roundTrip sends one JSON line and decodes one JSON line back.
func roundTrip(t *testing.T, socketPath string, req request) response {
	t.Helper()

	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	if err := json.NewEncoder(conn).Encode(req); err != nil {
		t.Fatalf("send: %v", err)
	}

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	if !scanner.Scan() {
		t.Fatal("no response from server")
	}

	var resp response
	if err := json.Unmarshal(scanner.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return resp
}

func TestPing(t *testing.T) {
	socketPath, _ := startTestServer(t, history.New(10))
	resp := roundTrip(t, socketPath, request{Cmd: "ping"})
	if !resp.OK {
		t.Errorf("ping failed: %s", resp.Error)
	}
}

func TestHistoryReturnsItemsNewestFirst(t *testing.T) {
	h := history.New(10)
	h.Add(history.NewItem("older", false))
	h.Add(history.NewItem("newer", false))

	socketPath, _ := startTestServer(t, h)
	resp := roundTrip(t, socketPath, request{Cmd: "history"})

	if !resp.OK || len(resp.Items) != 2 {
		t.Fatalf("expected 2 items, got ok=%v items=%d", resp.OK, len(resp.Items))
	}
	if resp.Items[0].Content != "newer" {
		t.Errorf("expected newest first, got %q", resp.Items[0].Content)
	}
}

func TestSelectCopiesItemToClipboard(t *testing.T) {
	h := history.New(10)
	item := history.NewItem("paste me", false)
	h.Add(item)

	socketPath, copied := startTestServer(t, h)
	resp := roundTrip(t, socketPath, request{Cmd: "select", ID: item.ID})

	if !resp.OK {
		t.Fatalf("select failed: %s", resp.Error)
	}
	if *copied != "paste me" {
		t.Errorf("clipboard got %q, want %q", *copied, "paste me")
	}
}

func TestSelectUnknownID(t *testing.T) {
	socketPath, _ := startTestServer(t, history.New(10))
	resp := roundTrip(t, socketPath, request{Cmd: "select", ID: "nope"})
	if resp.OK {
		t.Error("selecting unknown ID should fail")
	}
}

func TestUnknownCommandAndBadJSON(t *testing.T) {
	socketPath, _ := startTestServer(t, history.New(10))

	resp := roundTrip(t, socketPath, request{Cmd: "frobnicate"})
	if resp.OK {
		t.Error("unknown command should return ok=false")
	}

	// Raw bad JSON over the wire.
	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()
	if _, err := conn.Write([]byte("this is not json\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	scanner := bufio.NewScanner(conn)
	if !scanner.Scan() {
		t.Fatal("no response to bad JSON")
	}
	var r response
	if err := json.Unmarshal(scanner.Bytes(), &r); err != nil {
		t.Fatalf("server reply to bad JSON wasn't JSON: %v", err)
	}
	if r.OK {
		t.Error("bad JSON should return ok=false")
	}
}
