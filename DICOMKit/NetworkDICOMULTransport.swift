import Foundation
import Network

/// Errors reported by ``NetworkDICOMULTransport``.
public enum DICOMNetworkError: Error, Sendable, Equatable {
    case invalidPort
    case connectionFailed(String)
    case connectionClosed
    case incompletePDU
}

/// A TCP or TLS implementation of ``DICOMULTransport`` backed by Network.framework.
///
/// Construct with `.tcp` for conventional DICOM Upper Layer connections. Pass a
/// TLS-configured `NWParameters` only when the peer is explicitly configured
/// for DICOM TLS; standard DICOM ports do not negotiate TLS opportunistically.
public actor NetworkDICOMULTransport: DICOMULTransport {
    private let connection: NWConnection
    private var isConnected = false

    public init(host: String, port: UInt16, parameters: NWParameters = .tcp) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw DICOMNetworkError.invalidPort }
        connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
    }

    /// Starts the underlying connection. `send` and `receive` start it automatically.
    public func connect() async throws {
        guard !isConnected else { return }
        let _: Void = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: DICOMNetworkError.connectionFailed(error.debugDescription))
                case .cancelled:
                    continuation.resume(throwing: DICOMNetworkError.connectionClosed)
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
        isConnected = true
    }

    public func send(_ pdu: DICOMULPDU) async throws {
        try await connect()
        let bytes = try pdu.encoded()
        let _: Void = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: bytes, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: DICOMNetworkError.connectionFailed(error.debugDescription)) }
                else { continuation.resume() }
            })
        }
    }

    public func receive() async throws -> DICOMULPDU {
        try await connect()
        let header = try await receiveExactly(6)
        guard header[1] == 0 else { throw DICOMNetworkError.incompletePDU }
        let high = UInt32(header[2]) << 24 | UInt32(header[3]) << 16
        let low = UInt32(header[4]) << 8 | UInt32(header[5])
        let length = Int(high | low)
        return try DICOMULPDU.decode(header + (try await receiveExactly(length)))
    }

    public func close() async {
        isConnected = false
        connection.cancel()
    }

    private func receiveExactly(_ length: Int) async throws -> Data {
        guard length > 0 else { return Data() }
        var result = Data()
        while result.count < length {
            let remaining = length - result.count
            let received: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    if let error { continuation.resume(throwing: DICOMNetworkError.connectionFailed(error.debugDescription)) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else if complete { continuation.resume(throwing: DICOMNetworkError.connectionClosed) }
                    else { continuation.resume(throwing: DICOMNetworkError.incompletePDU) }
                }
            }
            result.append(received)
        }
        return result
    }
}
