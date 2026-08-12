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
    /// A QIDO-RS page had a non-positive limit or negative offset.
    case invalidQIDOPagination
    /// The server returned a status outside the successful HTTP range.
    case unsuccessfulHTTPStatus(Int)
    /// The server response was not HTTP.
    case invalidHTTPResponse
    /// A multipart response did not declare a boundary.
    case missingMultipartBoundary
    /// A multipart response did not contain a DICOM part.
    case invalidMultipartResponse
}

/// A QIDO-RS result page described by the standard `limit` and `offset` parameters.
public struct DICOMQIDOPagination: Sendable, Equatable {
    /// Maximum number of matching datasets to return. Must be greater than zero.
    public let limit: Int
    /// Number of matching datasets to skip. Must not be negative.
    public let offset: Int

    /// Creates a result page request.
    ///
    /// - Throws: ``DICOMwebError/invalidQIDOPagination`` if `limit` is not
    ///   positive or `offset` is negative.
    public init(limit: Int, offset: Int = 0) throws {
        guard limit > 0, offset >= 0 else { throw DICOMwebError.invalidQIDOPagination }
        self.limit = limit
        self.offset = offset
    }
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
    public func searchStudies(query: [URLQueryItem] = [], pagination: DICOMQIDOPagination? = nil) async throws -> Data {
        try await qidoSearch(path: ["studies"], query: query, pagination: pagination)
    }

    /// Performs a QIDO-RS series search within a study.
    public func searchSeries(studyInstanceUID: String, query: [URLQueryItem] = [], pagination: DICOMQIDOPagination? = nil) async throws -> Data {
        try await qidoSearch(path: ["studies", studyInstanceUID, "series"], query: query, pagination: pagination)
    }

    /// Performs a QIDO-RS instance search, optionally scoped to a series.
    public func searchInstances(studyInstanceUID: String, seriesInstanceUID: String? = nil, query: [URLQueryItem] = [], pagination: DICOMQIDOPagination? = nil) async throws -> Data {
        var path = ["studies", studyInstanceUID]
        if let seriesInstanceUID { path += ["series", seriesInstanceUID] }
        path.append("instances")
        return try await qidoSearch(path: path, query: query, pagination: pagination)
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

    /// Retrieves DICOM JSON metadata for one instance through WADO-RS.
    public func retrieveMetadata(studyInstanceUID: String, seriesInstanceUID: String, sopInstanceUID: String) async throws -> Data {
        try await retrieveData(path: ["studies", studyInstanceUID, "series", seriesInstanceUID, "instances", sopInstanceUID, "metadata"], accept: "application/dicom+json")
    }

    /// Retrieves and decodes DICOM JSON metadata for one instance through WADO-RS.
    ///
    /// WADO-RS metadata is an array of PS3.18 Annex F datasets. `BulkDataURI`
    /// values remain references and are not fetched implicitly.
    public func retrieveTypedMetadata(studyInstanceUID: String, seriesInstanceUID: String, sopInstanceUID: String) async throws -> [DICOMJSONDataset] {
        let data = try await retrieveMetadata(
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            sopInstanceUID: sopInstanceUID
        )
        return try JSONDecoder().decode([DICOMJSONDataset].self, from: data)
    }

    /// Retrieves a server-rendered representation of one instance through WADO-RS.
    ///
    /// The default `image/jpeg` has broad client support. Pass another rendered
    /// media type, such as `image/png`, only when the target server supports it.
    public func retrieveRenderedInstance(
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String,
        mediaType: String = "image/jpeg"
    ) async throws -> Data {
        try await retrieveData(
            path: ["studies", studyInstanceUID, "series", seriesInstanceUID, "instances", sopInstanceUID, "rendered"],
            accept: mediaType
        )
    }

    /// Retrieves an instance thumbnail through the WADO-RS thumbnail resource.
    public func retrieveThumbnail(
        studyInstanceUID: String,
        seriesInstanceUID: String,
        sopInstanceUID: String
    ) async throws -> Data {
        try await retrieveData(
            path: ["studies", studyInstanceUID, "series", seriesInstanceUID, "instances", sopInstanceUID, "thumbnail"],
            accept: "image/jpeg"
        )
    }

    /// Retrieves one or more WADO-RS frames. Frame numbers are one-based.
    public func retrieveFrames(studyInstanceUID: String, seriesInstanceUID: String, sopInstanceUID: String, frameNumbers: [Int]) async throws -> Data {
        guard !frameNumbers.isEmpty, frameNumbers.allSatisfy({ $0 > 0 }) else { throw DICOMwebError.invalidMultipartResponse }
        return try await retrieveData(path: ["studies", studyInstanceUID, "series", seriesInstanceUID, "instances", sopInstanceUID, "frames", frameNumbers.map(String.init).joined(separator: ",")], accept: "multipart/related")
    }

    /// Retrieves a BulkData URI returned by DICOM JSON metadata.
    public func retrieveBulkData(uri: URL) async throws -> Data {
        var request = URLRequest(url: uri)
        request.httpMethod = "GET"
        request.setValue("multipart/related", forHTTPHeaderField: "Accept")
        return try await perform(request).data
    }

    /// Stores DICOM Part 10 instances through STOW-RS and returns the server's DICOM JSON response.
    public func store(instances: [Data]) async throws -> Data {
        try await store(instances: instances, studyInstanceUID: nil)
    }

    /// Stores DICOM Part 10 instances through STOW-RS, optionally at a
    /// study-specific endpoint.
    public func store(instances: [Data], studyInstanceUID: String?) async throws -> Data {
        let boundary = "DICOMKit-\(UUID().uuidString)"
        var path = ["studies"]
        if let studyInstanceUID { path.append(studyInstanceUID) }
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/related; type=application/dicom; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(instances: instances, boundary: boundary)
        return try await perform(request).data
    }

    private func qidoSearch(path: [String], query: [URLQueryItem], pagination: DICOMQIDOPagination?) async throws -> Data {
        var components = URLComponents(url: endpoint(path), resolvingAgainstBaseURL: false)!
        var queryItems = query
        if let pagination {
            queryItems.append(URLQueryItem(name: "limit", value: String(pagination.limit)))
            queryItems.append(URLQueryItem(name: "offset", value: String(pagination.offset)))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/dicom+json", forHTTPHeaderField: "Accept")
        return try await perform(request).data
    }

    private func retrieveData(path: [String], accept: String) async throws -> Data {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "GET"
        request.setValue(accept, forHTTPHeaderField: "Accept")
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
