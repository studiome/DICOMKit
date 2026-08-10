import Foundation

/// The transport used by ``DICOMwebClient``.
///
/// Supplying a custom transport makes DICOMweb requests deterministic in tests
/// and lets applications add their own authentication or observability layer.
public protocol DICOMwebTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: DICOMwebTransport {}

/// Errors returned while constructing or handling DICOMweb requests.
public enum DICOMwebError: Error, Sendable, Equatable {
    /// The server returned a status outside the successful HTTP range.
    case unsuccessfulHTTPStatus(Int)
    /// The server response was not HTTP.
    case invalidHTTPResponse
    /// A multipart response did not declare a boundary.
    case missingMultipartBoundary
    /// A multipart response did not contain a DICOM part.
    case invalidMultipartResponse
}

/// An async client for the QIDO-RS, WADO-RS, and STOW-RS DICOMweb services.
///
/// The base URL is the DICOMweb service root, for example
/// `https://pacs.example.com/dicomweb`. The client has no implicit
/// authentication policy: customize its ``DICOMwebTransport`` when a server
/// requires credentials, headers, logging, or certificate handling.
public struct DICOMwebClient: Sendable {
    public let baseURL: URL
    private let transport: any DICOMwebTransport

    /// Creates a client using `URLSession.shared`.
    public init(baseURL: URL) {
        self.init(baseURL: baseURL, transport: URLSession.shared)
    }

    /// Creates a client using the supplied transport.
    public init(baseURL: URL, transport: any DICOMwebTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Performs a QIDO-RS study search and returns the DICOM JSON response.
    public func searchStudies(query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: endpoint(["studies"]), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        return try await perform(request).data
    }

    /// Retrieves one DICOM Part 10 instance through WADO-RS.
    ///
    /// Both a direct `application/dicom` response and a single-instance
    /// `multipart/related` response are accepted.
    public func retrieveInstance(
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String
    ) async throws -> DICOMFile {
        var request = URLRequest(url: endpoint([
            "studies", studyInstanceUID,
            "series", seriesInstanceUID,
            "instances", sopInstanceUID
        ]))
        request.httpMethod = "GET"
        request.setValue("multipart/related; type=application/dicom", forHTTPHeaderField: "Accept")
        let result = try await perform(request)
        let data: Data
        if contentType(from: result.response)?.lowercased().hasPrefix("multipart/") == true {
            data = try firstDICOMPart(in: result.data, contentType: contentType(from: result.response))
        } else {
            data = result.data
        }
        return try DICOMFile(data: data)
    }

    /// Stores DICOM Part 10 instances through STOW-RS and returns the server's DICOM JSON response.
    public func store(instances: [Data]) async throws -> Data {
        let boundary = "DICOMKit-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint(["studies"]))
        request.httpMethod = "POST"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/related; type=application/dicom; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(instances: instances, boundary: boundary)
        return try await perform(request).data
    }

    private func endpoint(_ components: [String]) -> URL {
        components.reduce(baseURL) { $0.appendingPathComponent($1) }
    }

    private func perform(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let (data, urlResponse) = try await transport.data(for: request)
        guard let response = urlResponse as? HTTPURLResponse else { throw DICOMwebError.invalidHTTPResponse }
        guard (200...299).contains(response.statusCode) else { throw DICOMwebError.unsuccessfulHTTPStatus(response.statusCode) }
        return (data, response)
    }
}

private func multipartBody(instances: [Data], boundary: String) -> Data {
    var result = Data()
    for instance in instances {
        result.append(Data("--\(boundary)\r\nContent-Type: application/dicom\r\n\r\n".utf8))
        result.append(instance)
        result.append(Data("\r\n".utf8))
    }
    result.append(Data("--\(boundary)--\r\n".utf8))
    return result
}

private func contentType(from response: HTTPURLResponse) -> String? {
    response.value(forHTTPHeaderField: "Content-Type")
}

private func firstDICOMPart(in data: Data, contentType: String?) throws -> Data {
    guard let contentType,
          let boundaryValue = contentType.split(separator: ";").map(String.init).first(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("boundary=") }) else {
        throw DICOMwebError.missingMultipartBoundary
    }
    let boundary = boundaryValue
        .trimmingCharacters(in: .whitespaces)
        .dropFirst("boundary=".count)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    let marker = Data("--\(boundary)".utf8)
    let headerSeparator = Data("\r\n\r\n".utf8)
    let partTerminator = Data("\r\n--\(boundary)".utf8)
    guard let opening = data.range(of: marker),
          let headersEnd = data.range(of: headerSeparator, options: [], in: opening.upperBound..<data.endIndex),
          let bodyEnd = data.range(of: partTerminator, options: [], in: headersEnd.upperBound..<data.endIndex) else {
        throw DICOMwebError.invalidMultipartResponse
    }
    return data.subdata(in: headersEnd.upperBound..<bodyEnd.lowerBound)
}
