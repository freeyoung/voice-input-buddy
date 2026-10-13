import Foundation
import Testing
@testable import VoiceInputBuddy

/// Runs entirely through URLProtocol; none of these requests reach the network.
private final class FeedDownloadFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = request.url!.lastPathComponent
        let limit = 1_024 * 1_024
        let size = mode == "large-body" ? limit + 1 : (mode == "exact" ? limit : 4)
        let headers = mode == "large-header" ? ["Content-Length": "1048577"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: mode == "error" ? 404 : 200,
            httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let chunk = Data(repeating: 65, count: 16 * 1_024)
        var remaining = size
        while remaining > 0 {
            let amount = min(chunk.count, remaining)
            client?.urlProtocol(self, didLoad: Data(chunk.prefix(amount)))
            remaining -= amount
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Bounded update feed download")
struct UpdateFeedDownloadTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedDownloadFixture.self]
        return URLSession(configuration: configuration)
    }

    @Test(arguments: ["small", "exact"])
    func acceptedPayloadMatchesResponse(mode: String) async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let data = try await UpdateFeedResolver.loadFeedData(
            from: URL(string: "https://feed.example.invalid/" + mode)!, session: session)
        #expect(data == Data(repeating: 65, count: mode == "exact" ? 1_024 * 1_024 : 4))
    }

    @Test(arguments: ["large-header", "large-body", "error"])
    func refusesOversizedOrFailedResponse(mode: String) async {
        let session = session()
        defer { session.invalidateAndCancel() }
        await #expect(throws: UpdateFeedResolutionError.self) {
            try await UpdateFeedResolver.loadFeedData(
                from: URL(string: "https://feed.example.invalid/" + mode)!, session: session)
        }
    }
}
