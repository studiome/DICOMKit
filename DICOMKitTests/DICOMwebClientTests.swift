import Foundation
import Testing
@testable import DICOMKit

struct DICOMwebClientTests {
    @Test func retriesTransientDICOMwebResponsesWhenConfigured() async throws {
        let transport = SequencedDICOMwebTransport(statusCodes: [503, 200])
        let client = DICOMwebClient(
            baseURL: URL(string: "https://example.test/dicomweb")!,
            transport: transport,
            retryPolicy: try DICOMwebRetryPolicy(maximumAttempts: 2)
        )

        _ = try await client.searchStudies()

        #expect(transport.requestCount == 2)
    }

    @Test func wadoRetrievesRenderedImageAndThumbnail() async throws {
        let transport = CapturingDICOMwebTransport(response: Data("image".utf8))
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb")!, transport: transport)

        _ = try await client.retrieveRenderedInstance(studyInstanceUID: "1.2.3", seriesInstanceUID: "4.5.6", sopInstanceUID: "7.8.9", mediaType: "image/png")
        _ = try await client.retrieveThumbnail(studyInstanceUID: "1.2.3", seriesInstanceUID: "4.5.6", sopInstanceUID: "7.8.9")

        #expect(transport.requests.map { $0.url?.path } == [
            "/dicomweb/studies/1.2.3/series/4.5.6/instances/7.8.9/rendered",
            "/dicomweb/studies/1.2.3/series/4.5.6/instances/7.8.9/thumbnail"
        ])
        #expect(transport.requests.map { $0.value(forHTTPHeaderField: "Accept") } == ["image/png", "image/jpeg"])
    }

    @Test func qidoSearchAddsPaginationParameters() async throws {
        let transport = CapturingDICOMwebTransport(response: Data("[]".utf8))
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb")!, transport: transport)

        _ = try await client.searchStudies(
            query: [URLQueryItem(name: "PatientName", value: "Doe*")],
            pagination: try DICOMQIDOPagination(limit: 25, offset: 50)
        )

        let queryItems = URLComponents(url: try #require(transport.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(queryItems == [
            URLQueryItem(name: "PatientName", value: "Doe*"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "offset", value: "50")
        ])
    }

    @Test func wadoDecodesTypedMetadata() async throws {
        let response = Data("[{\"00100010\":{\"vr\":\"PN\",\"Value\":[{\"Alphabetic\":\"Doe^Jane\"}]}}]".utf8)
        let transport = CapturingDICOMwebTransport(response: response)
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb")!, transport: transport)

        let datasets = try await client.retrieveTypedMetadata(studyInstanceUID: "1.2.3", seriesInstanceUID: "4.5.6", sopInstanceUID: "7.8.9")

        #expect(datasets.count == 1)
        #expect(try #require(datasets[0].elements["00100010"]?.value) == [.personName(DICOMJSONPersonName(alphabetic: "Doe^Jane"))])
    }

    @Test func wadoRetrievesMetadataFramesAndBulkData() async throws {
        let transport = CapturingDICOMwebTransport(response: Data("payload".utf8))
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb")!, transport: transport)

        _ = try await client.retrieveMetadata(studyInstanceUID: "1.2.3", seriesInstanceUID: "4.5.6", sopInstanceUID: "7.8.9")
        _ = try await client.retrieveFrames(studyInstanceUID: "1.2.3", seriesInstanceUID: "4.5.6", sopInstanceUID: "7.8.9", frameNumbers: [1, 3])
        _ = try await client.retrieveBulkData(uri: URL(string: "https://example.test/bulk/abc")!)

        #expect(transport.requests.map { $0.url?.path } == [
            "/dicomweb/studies/1.2.3/series/4.5.6/instances/7.8.9/metadata",
            "/dicomweb/studies/1.2.3/series/4.5.6/instances/7.8.9/frames/1,3",
            "/bulk/abc"
        ])
        #expect(transport.requests[0].value(forHTTPHeaderField: "Accept") == "application/dicom+json")
        #expect(transport.requests[1].value(forHTTPHeaderField: "Accept") == "multipart/related")
    }
    @Test func qidoSearchesSeriesAndInstances() async throws {
        let transport = CapturingDICOMwebTransport(response: Data("[]".utf8))
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb")!, transport: transport)

        _ = try await client.searchSeries(studyInstanceUID: "1.2.3")
        _ = try await client.searchInstances(studyInstanceUID: "1.2.3", seriesInstanceUID: "4.5.6", query: [URLQueryItem(name: "ModalitiesInStudy", value: "CT")])

        #expect(transport.requests.map { $0.url?.path } == [
            "/dicomweb/studies/1.2.3/series",
            "/dicomweb/studies/1.2.3/series/4.5.6/instances"
        ])
        #expect(URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "ModalitiesInStudy", value: "CT")])
    }

    @Test func qidoSearchBuildsStudiesRequest() async throws {
        let transport = CapturingDICOMwebTransport(response: Data("[]".utf8))
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb")!, transport: transport)

        let response = try await client.searchStudies(query: [URLQueryItem(name: "PatientName", value: "Doe*")])

        #expect(response == Data("[]".utf8))
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/dicomweb/studies")
        #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first == URLQueryItem(name: "PatientName", value: "Doe*"))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/dicom+json")
    }

    @Test func wadoRetrievesPart10InstanceFromMultipartResponse() async throws {
        let dataset = DICOMDataset(elements: [DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8))])
        let encoded = try DICOMWriter.write(dataset: dataset)
        let boundary = "dicomkit-boundary"
        let response = multipart(body: encoded, boundary: boundary)
        let transport = CapturingDICOMwebTransport(
            response: response,
            headers: ["Content-Type": "multipart/related; type=application/dicom; boundary=\"\(boundary)\""]
        )
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb/")!, transport: transport)

        let file = try await client.retrieveInstance(studyInstanceUID: "1.2.3", seriesInstanceUID: "4.5.6", sopInstanceUID: "7.8.9")

        #expect(file.dataset[.patientName]?.stringValue == "Doe^Jane")
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/dicomweb/studies/1.2.3/series/4.5.6/instances/7.8.9")
        #expect(request.value(forHTTPHeaderField: "Accept") == "multipart/related; type=application/dicom")
    }

    @Test func stowStoresPart10InstancesAsMultipartRequest() async throws {
        let encoded = try DICOMWriter.write(dataset: DICOMDataset(elements: [DICOMElement(tag: .patientName, vr: .PN, value: Data("Doe^Jane".utf8))]))
        let transport = CapturingDICOMwebTransport(response: Data("{}".utf8), statusCode: 200)
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb")!, transport: transport)

        _ = try await client.store(instances: [encoded])

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/dicomweb/studies")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/related; type=application/dicom; boundary=") == true)
        #expect(request.httpBody?.range(of: encoded) != nil)
    }

    @Test func stowStoresAtStudyEndpoint() async throws {
        let transport = CapturingDICOMwebTransport(response: Data("{}".utf8))
        let client = DICOMwebClient(baseURL: URL(string: "https://example.test/dicomweb")!, transport: transport)

        _ = try await client.store(instances: [Data([0])], studyInstanceUID: "1.2.3")

        #expect(transport.requests.first?.url?.path == "/dicomweb/studies/1.2.3")
    }
}

private final class CapturingDICOMwebTransport: DICOMwebTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let response: Data
    private let statusCode: Int
    private let headers: [String: String]

    init(response: Data, statusCode: Int = 200, headers: [String: String] = [:]) {
        self.response = response
        self.statusCode = statusCode
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (response, HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: headers)!)
    }
}

private final class SequencedDICOMwebTransport: DICOMwebTransport, @unchecked Sendable {
    private var statusCodes: [Int]
    private(set) var requestCount = 0

    init(statusCodes: [Int]) { self.statusCodes = statusCodes }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        let statusCode = statusCodes.removeFirst()
        return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: [:])!)
    }
}

private func multipart(body: Data, boundary: String) -> Data {
    var result = Data("--\(boundary)\r\nContent-Type: application/dicom\r\n\r\n".utf8)
    result.append(body)
    result.append(Data("\r\n--\(boundary)--\r\n".utf8))
    return result
}
