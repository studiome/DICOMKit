import Foundation
import Network
import Testing
@testable import DICOMKit
import DICOMKitNetworking

/// A peer that declares an absurd PDU length in the 6-byte Upper Layer PDU
/// header (PS3.8 9.3) before any association has negotiated Maximum Length
/// Received `(0051H)` can otherwise force ``NetworkDICOMULTransport/receive()``
/// to block waiting for gigabytes of bytes that never arrive. This exercises
/// that over a real loopback TCP connection, using a raw `NWListener` (rather
/// than `NetworkDICOMULListener`) so the test can hand-craft a header
/// `NetworkDICOMULTransport.send` itself would never produce.
struct NetworkDICOMULTransportSafetyTests {
    @Test func receiveRejectsAPeerDeclaredPDULengthPastTheMaximum() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let accepted = AcceptedConnectionBox()
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
            accepted.set(connection)
        }
        listener.start(queue: .global(qos: .userInitiated))
        defer { listener.cancel() }

        var boundPort: UInt16?
        for _ in 0..<200 {
            if let port = listener.port?.rawValue, port != 0 { boundPort = port; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let port = try #require(boundPort)

        let client = try NetworkDICOMULTransport(host: "127.0.0.1", port: port)
        try await client.connect()

        var serverConnection: NWConnection?
        for _ in 0..<200 {
            if let connection = accepted.get() { serverConnection = connection; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let server = try #require(serverConnection)
        defer { server.cancel() }

        // PDU type 0x01 (arbitrary), reserved byte 0, length 0xFFFFFFFF: a
        // syntactically valid header declaring ~4.3 GiB of payload that
        // this peer never actually sends.
        let maliciousHeader = Data([0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            server.send(content: maliciousHeader, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }

        // Races `client.receive()` against a timeout, exactly as
        // `DICOMAssociation.receiveRawPDU()` does for a real transport:
        // `group.cancelAll()` alone cannot free a `receive()` blocked
        // inside `NWConnection.receive`, which ignores Task cancellation,
        // and `withThrowingTaskGroup` awaits every child before this
        // closure may return -- so `client.close()` must happen here,
        // before rethrowing, so the transport unblocks its receiver before
        // anything awaits it.
        let result: Result<DICOMULPDU, Error>
        do {
            let pdu = try await withThrowingTaskGroup(of: DICOMULPDU.self) { group in
                group.addTask { try await client.receive() }
                group.addTask {
                    try await Task.sleep(for: .seconds(3))
                    throw TransportSafetyTestTimeoutError()
                }
                do {
                    guard let first = try await group.next() else { throw TransportSafetyTestTimeoutError() }
                    group.cancelAll()
                    return first
                } catch {
                    group.cancelAll()
                    await client.close()
                    throw error
                }
            }
            result = .success(pdu)
        } catch {
            result = .failure(error)
        }

        switch result {
        case .success:
            Issue.record("expected receive() to reject the oversized declared PDU length")
        case .failure(let error):
            #expect(error as? DICOMNetworkError == .pduTooLarge)
        }
    }

    /// `connect()` only sets `isConnected = true` after its `await`, so two
    /// concurrent callers can both observe `!isConnected`, both install
    /// their own `stateUpdateHandler`, and both call `connection.start()`.
    /// Only the state update handler set *last* ever fires: the other
    /// caller's continuation is orphaned and never resumes.
    ///
    /// This polls a completion flag rather than awaiting the connect
    /// tasks directly: an orphaned continuation resumes *never*, not
    /// merely slowly, and awaiting it -- even inside a race against a
    /// timeout -- would hang this test forever, since nothing (not even
    /// closing the transport) can free a continuation that no callback
    /// references anymore.
    @Test func concurrentConnectCallsBothCompleteRatherThanOrphaningAContinuation() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in connection.start(queue: .global(qos: .userInitiated)) }
        listener.start(queue: .global(qos: .userInitiated))
        defer { listener.cancel() }

        var boundPort: UInt16?
        for _ in 0..<200 {
            if let port = listener.port?.rawValue, port != 0 { boundPort = port; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let port = try #require(boundPort)

        let client = try NetworkDICOMULTransport(host: "127.0.0.1", port: port)
        let firstFlag = ConnectCompletionFlag()
        let secondFlag = ConnectCompletionFlag()
        Task {
            do { try await client.connect(); firstFlag.markDone(.success(())) }
            catch { firstFlag.markDone(.failure(error)) }
        }
        Task {
            do { try await client.connect(); secondFlag.markDone(.success(())) }
            catch { secondFlag.markDone(.failure(error)) }
        }

        var firstResult: Result<Void, Error>?
        var secondResult: Result<Void, Error>?
        for _ in 0..<300 {
            firstResult = firstResult ?? firstFlag.snapshot()
            secondResult = secondResult ?? secondFlag.snapshot()
            if firstResult != nil, secondResult != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        if case .failure(let error) = firstResult { Issue.record("first connect() call failed: \(error)") }
        if case .failure(let error) = secondResult { Issue.record("second connect() call failed: \(error)") }
        #expect(firstResult != nil, "first connect() call never completed (orphaned continuation)")
        #expect(secondResult != nil, "second connect() call never completed (orphaned continuation)")
    }
}

/// Set exactly once, from whichever `Task` finishes; read via polling so a
/// test can bound its wait without ever blocking on the value directly.
private final class ConnectCompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func markDone(_ result: Result<Void, Error>) {
        lock.lock(); defer { lock.unlock() }
        self.result = result
    }

    func snapshot() -> Result<Void, Error>? {
        lock.lock(); defer { lock.unlock() }
        return result
    }
}

/// Bridges a callback-delivered `NWConnection` into `async` code.
private final class AcceptedConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NWConnection?

    func set(_ connection: NWConnection) {
        lock.lock(); defer { lock.unlock() }
        self.connection = connection
    }

    func get() -> NWConnection? {
        lock.lock(); defer { lock.unlock() }
        return connection
    }
}

private struct TransportSafetyTestTimeoutError: Error {}
