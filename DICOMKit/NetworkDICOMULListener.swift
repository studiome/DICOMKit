import Foundation
import Network

/// A Network.framework listener that accepts inbound DICOM Upper Layer connections and
/// hands each one back as a ``NetworkDICOMULTransport``.
public actor NetworkDICOMULListener {
    private let listener: NWListener
    private var boundPort: UInt16?
    private var pendingConnections: [NWConnection] = []
    private var pendingContinuations: [CheckedContinuation<NetworkDICOMULTransport, Error>] = []
    private var closedError: Error?

    public init(port: UInt16, parameters: NWParameters = .tcp) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw DICOMNetworkError.invalidPort }
        listener = try NWListener(using: parameters, on: endpointPort)
    }

    /// The actually-bound port. Available once the listener reaches the ready state,
    /// which is needed to learn the assigned port when constructed with port 0.
    public var port: UInt16? { boundPort }

    /// Starts listening. Connections that arrive before ``accept()`` is called are queued.
    public func start() throws {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handle(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handle(connection) }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    /// Returns the next inbound connection as a transport, waiting if none has arrived yet.
    public func accept() async throws -> NetworkDICOMULTransport {
        if let closedError { throw closedError }
        if !pendingConnections.isEmpty {
            return NetworkDICOMULTransport(connection: pendingConnections.removeFirst())
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }

    /// Stops listening. Causes any pending or subsequent ``accept()`` to throw
    /// ``DICOMNetworkError/connectionClosed``.
    public func stop() {
        listener.cancel()
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            boundPort = listener.port?.rawValue
        case .failed(let error):
            fail(DICOMNetworkError.listenerFailed(error.debugDescription))
        case .cancelled:
            fail(DICOMNetworkError.connectionClosed)
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        if !pendingContinuations.isEmpty {
            pendingContinuations.removeFirst().resume(returning: NetworkDICOMULTransport(connection: connection))
        } else {
            pendingConnections.append(connection)
        }
    }

    private func fail(_ error: Error) {
        guard closedError == nil else { return }
        closedError = error
        let waiters = pendingContinuations
        pendingContinuations.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
    }
}
