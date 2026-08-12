import Foundation
import Network

/// A Network.framework listener that accepts inbound DICOM Upper Layer connections and
/// hands each one back as a ``NetworkDICOMULTransport``.
public actor NetworkDICOMULListener {
    private let listener: NWListener
    private var boundPort: UInt16?
    private var pendingConnections: [NWConnection] = []
    private var pendingWaiters: [(id: Int, continuation: CheckedContinuation<NetworkDICOMULTransport, Error>)] = []
    private var nextWaiterID = 0
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
    /// Cancelling the awaiting task throws `CancellationError` promptly instead of leaking
    /// the wait.
    public func accept() async throws -> NetworkDICOMULTransport {
        if let closedError { throw closedError }
        if !pendingConnections.isEmpty {
            return NetworkDICOMULTransport(connection: pendingConnections.removeFirst())
        }
        if Task.isCancelled { throw CancellationError() }
        let id = nextWaiterID
        nextWaiterID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NetworkDICOMULTransport, Error>) in
                pendingWaiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Stops listening. Cancels every queued inbound connection so none is left established
    /// and unreachable, then causes any pending or subsequent ``accept()`` to throw
    /// ``DICOMNetworkError/connectionClosed``.
    public func stop() {
        let connections = pendingConnections
        pendingConnections.removeAll()
        for connection in connections { connection.cancel() }
        listener.cancel()
    }

    private func cancelWaiter(_ id: Int) {
        guard let index = pendingWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = pendingWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
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
        if !pendingWaiters.isEmpty {
            pendingWaiters.removeFirst().continuation.resume(returning: NetworkDICOMULTransport(connection: connection))
        } else {
            pendingConnections.append(connection)
        }
    }

    private func fail(_ error: Error) {
        guard closedError == nil else { return }
        closedError = error
        let waiters = pendingWaiters
        pendingWaiters.removeAll()
        for waiter in waiters { waiter.continuation.resume(throwing: error) }
    }
}
