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
