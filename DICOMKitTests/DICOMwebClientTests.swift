import Foundation
import Testing
@testable import DICOMKit

struct DICOMwebClientTests {
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

private func multipart(body: Data, boundary: String) -> Data {
    var result = Data("--\(boundary)\r\nContent-Type: application/dicom\r\n\r\n".utf8)
    result.append(body)
    result.append(Data("\r\n--\(boundary)--\r\n".utf8))
    return result
}
