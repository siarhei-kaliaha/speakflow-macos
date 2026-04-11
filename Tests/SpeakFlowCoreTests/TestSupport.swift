import Foundation
@testable import SpeakFlowCore

final class MockNetworkSession: NetworkSession {
    var lastRequest: URLRequest?
    var responseData: Data
    var response: URLResponse
    var error: Error?

    init(
        responseData: Data = Data(),
        response: URLResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!,
        error: Error? = nil
    ) {
        self.responseData = responseData
        self.response = response
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error {
            throw error
        }
        return (responseData, response)
    }
}

func makeTempDirectory(function: String = #function) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SpeakFlowTests-\(function)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
