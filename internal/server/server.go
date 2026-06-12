// Package server exposes the clipboard history to the SwiftUI app over a
// Unix domain socket.
//
// Why a Unix socket (vs a TCP port): it lives at a filesystem path with
// normal file permissions, so only this user can connect; there's no
// "port already in use" clash; and no firewall dialog. It behaves exactly
// like a network connection in Go (net.Listener / net.Conn), so the code
// looks like a tiny web server.
//
// Protocol: one JSON object per line in each direction ("line-delimited
// JSON"). Newlines make message boundaries trivial — read until \n,
// parse, respond. You can poke it by hand:
//
//	echo '{"cmd":"history"}' | nc -U ~/Library/"Application Support"/GlassClip/glassclipd.sock
//
// Commands:
//	{"cmd":"ping"}                 → {"ok":true}
//	{"cmd":"history"}              → {"ok":true,"items":[...]}
//	{"cmd":"select","id":"<id>"}   → puts that item on the clipboard, {"ok":true}
//	{"cmd":"clear"}                → {"ok":true}
package server

import (
	"bufio"
	"encoding/json"
	"errors"
	"net"
	"os"

	"github.com/sathvik458/glassclip/internal/history"
)

// request is what the UI sends us. ID is only used by "select".
// `omitempty` means the field is dropped from JSON when empty.
type request struct {
	Cmd string `json:"cmd"`
	ID  string `json:"id,omitempty"`
}

// response is what we send back. Exactly one shape for every command
// keeps the Swift decoding code to a single struct.
type response struct {
	OK    bool                    `json:"ok"`
	Error string                  `json:"error,omitempty"`
	Items []history.ClipboardItem `json:"items,omitempty"`
}

// Server owns the listening socket.
//
// Why these fields exist:
//   - history:      the shared item list (same instance the monitor writes to).
//   - setClipboard: injected function that writes to the real clipboard.
//                   Injection (instead of calling clipboard.SetText directly)
//                   keeps this package macOS-free and lets tests use a fake.
//   - listener:     kept so Close() can shut the socket down from another
//                   goroutine, which unblocks the Accept loop.
type Server struct {
	history      *history.History
	setClipboard func(string) error
	listener     net.Listener
}

// New wires up a server. It does not start listening yet.
func New(h *history.History, setClipboard func(string) error) *Server {
	return &Server{history: h, setClipboard: setClipboard}
}

// ListenAndServe blocks, accepting connections until Close is called.
//
// Concurrency: each accepted connection gets its own goroutine
// (go s.handleConn(conn)) — the standard Go server pattern. Goroutines
// are cheap (~few KB), and it means a slow client can never block others.
func (s *Server) ListenAndServe(socketPath string) error {
	// If the daemon crashed last time, a stale socket file is left
	// behind and Listen would fail with "address already in use".
	// Removing it first makes restarts reliable.
	_ = os.Remove(socketPath)

	ln, err := net.Listen("unix", socketPath)
	if err != nil {
		return err
	}
	s.listener = ln

	for {
		conn, err := ln.Accept()
		if err != nil {
			// net.ErrClosed means Close() was called — a normal
			// shutdown, not a failure.
			if errors.Is(err, net.ErrClosed) {
				return nil
			}
			return err
		}
		go s.handleConn(conn)
	}
}

// Close stops the listener, which unblocks ListenAndServe.
func (s *Server) Close() error {
	if s.listener == nil {
		return nil
	}
	return s.listener.Close()
}

// handleConn serves one client connection: read a line, handle it,
// write a line, repeat until the client hangs up.
func (s *Server) handleConn(conn net.Conn) {
	defer conn.Close()

	scanner := bufio.NewScanner(conn)
	// Scanner's default line limit is 64KB. A clipboard item can be up
	// to 1MB, and a "history" response holds ten of them — raise the
	// limit so big requests/items don't kill the connection.
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)

	encoder := json.NewEncoder(conn) // Encode() writes JSON + "\n"

	for scanner.Scan() {
		var req request
		if err := json.Unmarshal(scanner.Bytes(), &req); err != nil {
			_ = encoder.Encode(response{OK: false, Error: "invalid JSON: " + err.Error()})
			continue
		}
		if err := encoder.Encode(s.handle(req)); err != nil {
			return // client went away mid-write; nothing to do
		}
	}
}

// handle is pure request → response logic, with no I/O. Keeping it
// separate from handleConn makes it directly unit-testable.
func (s *Server) handle(req request) response {
	switch req.Cmd {
	case "ping":
		return response{OK: true}

	case "history":
		return response{OK: true, Items: s.history.All()}

	case "select":
		item, ok := s.history.Get(req.ID)
		if !ok {
			return response{OK: false, Error: "no item with id " + req.ID}
		}
		if err := s.setClipboard(item.Content); err != nil {
			return response{OK: false, Error: "clipboard write failed: " + err.Error()}
		}
		return response{OK: true}

	case "clear":
		s.history.Clear()
		return response{OK: true}

	default:
		return response{OK: false, Error: "unknown command: " + req.Cmd}
	}
}
