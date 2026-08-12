import Foundation
import Network
import Testing
@testable import DICOMKit

/// Exercises ``NetworkDICOMULListener`` together with ``NetworkDICOMULTransport`` over a real
/// loopback TCP connection. If the sandbox refuses to bind or connect a loopback socket this
/// test fails loudly rather than being weakened or removed.
struct NetworkDICOMULListenerTests {
    @Test func listenerAcceptsConnectionAndRoundTripsAssociationPDUs() async throws {
        try await withTimeout(seconds: 10) {
            let listener = try NetworkDICOMULListener(port: 0)
            try await listener.start()

            var boundPort: UInt16?
            for _ in 0..<200 {
                if let port = await listener.port { boundPort = port; break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard let boundPort else {
                Issue.record("listener did not report a bound port")
                await listener.stop()
                return
            }

            let request = DICOMAssociationRequest(calledAETitle: "SCP", callingAETitle: "SCU", presentationContexts: [.init(id: 1, abstractSyntaxUID: "1.2.840.10008.1.1", transferSyntaxUIDs: ["1.2.840.10008.1.2"])])
            let acceptance = DICOMAssociationAcceptance(calledAETitle: "SCP", callingAETitle: "SCU", presentationContexts: [.init(id: 1, result: .acceptance, transferSyntaxUID: "1.2.840.10008.1.2")])

            async let server: DICOMULPDU = {
                let serverTransport = try await listener.accept()
                let received = try await serverTransport.receive()
                try await serverTransport.send(.associationAcceptance(acceptance))
                await serverTransport.close()
                return received
            }()

            let client = try NetworkDICOMULTransport(host: "127.0.0.1", port: boundPort)
            try await client.send(.associationRequest(request))
            let clientReceived = try await client.receive()
            await client.close()

            let serverReceived = try await server
            await listener.stop()

            guard case .associationRequest(let decodedRequest) = serverReceived else {
                Issue.record("server did not decode an association request"); return
            }
            guard case .associationAcceptance(let decodedAcceptance) = clientReceived else {
                Issue.record("client did not decode an association acceptance"); return
            }
            #expect(decodedRequest == request)
            #expect(decodedAcceptance == acceptance)
        }
    }

    @Test func acceptThrowsCancellationErrorPromptlyWhenAwaitingTaskIsCancelled() async throws {
        try await withTimeout(seconds: 10) {
            let listener = try NetworkDICOMULListener(port: 0)
            try await listener.start()
            try await Self.waitForBoundPort(of: listener)

            let waiter = Task { try await listener.accept() }
            // Give accept() a moment to reach its suspension point before cancelling.
            try await Task.sleep(for: .milliseconds(20))
            waiter.cancel()

            await #expect(throws: CancellationError.self) { try await waiter.value }
            await listener.stop()
        }
    }

    @Test func acceptThrowsConnectionClosedAfterStop() async throws {
        try await withTimeout(seconds: 10) {
            let listener = try NetworkDICOMULListener(port: 0)
            try await listener.start()
            try await Self.waitForBoundPort(of: listener)

            await listener.stop()

            await #expect(throws: DICOMNetworkError.connectionClosed) { try await listener.accept() }
        }
    }

    private static func waitForBoundPort(of listener: NetworkDICOMULListener) async throws {
        for _ in 0..<200 {
            if await listener.port != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("listener did not report a bound port")
    }
}

private struct TestTimeoutError: Error {}

/// Races `operation` against a deadline so a transport failure cannot hang the suite.
private func withTimeout<T: Sendable>(seconds: Double, operation: @Sendable @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TestTimeoutError()
        }
        guard let result = try await group.next() else { throw TestTimeoutError() }
        group.cancelAll()
        return result
    }
}
