// SocketClient.swift — the Swift side of the unix-socket protocol.
//
// Counterpart of Go's internal/server: we dial the socket, write one JSON
// line, read one JSON line back. We use Apple's Network framework
// (NWConnection), which supports unix domain sockets and plays nicely
// with Swift's async/await.
//
// Design choice: one short-lived connection per request. The daemon is
// on the same machine, so connection setup is microseconds — and
// stateless connections mean no reconnect logic when the daemon restarts.

import Foundation
import Network

enum SocketError: LocalizedError {
    case daemonUnreachable
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .daemonUnreachable:
            return "Can't reach glassclipd — is the daemon running?"
        case .badResponse(let detail):
            return "Bad response from daemon: \(detail)"
        }
    }
}

final class SocketClient {
    /// Same path the Go daemon listens on (see cmd/glassclipd/main.go).
    private let socketPath = NSHomeDirectory()
        + "/Library/Application Support/GlassClip/glassclipd.sock"

    private let decoder = JSONDecoder.glassClip()

    // MARK: Public API (one method per daemon command)

    func history() async throws -> [ClipboardItem] {
        let response = try await send(["cmd": "history"])
        return response.items ?? []
    }

    /// Asks the daemon to put item `id` back on the clipboard.
    func select(id: String) async throws {
        let response = try await send(["cmd": "select", "id": id])
        if !response.ok {
            throw SocketError.badResponse(response.error ?? "unknown error")
        }
    }

    // MARK: Wire plumbing

    /// Performs one request/response round trip.
    private func send(_ request: [String: String]) async throws -> ServerResponse {
        let connection = NWConnection(
            to: .unix(path: socketPath),
            using: .tcp // parameter set used for stream sockets; fine for unix too
        )
        // Whatever happens, close the connection when we're done.
        defer { connection.cancel() }

        try await start(connection)

        var line = try JSONSerialization.data(withJSONObject: request)
        line.append(0x0A) // '\n' — the daemon reads line-delimited JSON
        try await sendData(connection, line)

        let responseData = try await receiveLine(connection)
        do {
            return try decoder.decode(ServerResponse.self, from: responseData)
        } catch {
            throw SocketError.badResponse(error.localizedDescription)
        }
    }

    /// Waits until the connection is ready (or fails).
    ///
    /// withCheckedThrowingContinuation bridges callback-style APIs into
    /// async/await: we "park" here until the state handler resumes us.
    /// The handler can fire for several state changes (and on any
    /// queue), but a continuation must be resumed EXACTLY once — the
    /// OneShot flag below guarantees that, with a lock so it's safe
    /// even under Swift 6's strict concurrency checking. (A plain
    /// captured `var resumed` here is a data race — the compiler
    /// rightly rejects it.)
    private func start(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = OneShot()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.tryClaim() { cont.resume() }
                case .failed, .waiting:
                    // .waiting means "can't connect yet, will retry".
                    // For a local daemon that's effectively "not
                    // running", so fail fast instead of hanging.
                    if once.tryClaim() { cont.resume(throwing: SocketError.daemonUnreachable) }
                default:
                    break // .setup, .preparing — just wait
                }
            }
            connection.start(queue: .global())
        }
    }

    private func sendData(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    /// Reads until the first '\n'. The daemon sends exactly one JSON
    /// line per request, but TCP-style streams can deliver it in
    /// arbitrary chunks — so we accumulate until the newline shows up.
    private func receiveLine(_ connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try await receiveChunk(connection)
            if chunk.isEmpty {
                throw SocketError.badResponse("connection closed mid-response")
            }
            buffer.append(chunk)
            if let newline = buffer.firstIndex(of: 0x0A) {
                return buffer.prefix(upTo: newline)
            }
        }
    }

    private func receiveChunk(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(returning: Data()) // peer closed
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
    }
}

/// A tiny thread-safe "claim it once" flag — Swift's equivalent of what
/// Go's sync.Once does. tryClaim() returns true for exactly one caller,
/// no matter how many threads race on it.
///
/// @unchecked Sendable: we promise the compiler this is thread-safe
/// (it is — every access happens under the lock).
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func tryClaim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
