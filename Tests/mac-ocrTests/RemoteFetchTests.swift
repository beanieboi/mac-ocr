import Foundation
import Testing

@testable import MacOcrCore

/// `fetchRemoteData` enforces the URL input size cap and surfaces HTTP/empty
/// failures. Uses a stub `URLProtocol` so no real network is touched.
@Suite(.serialized) struct RemoteFetchTests {
	private let url = URL(string: "https://example.test/input")!

	private func stubbedSession() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [StubURLProtocol.self]
		return URLSession(configuration: configuration)
	}

	@Test func rejectsResponseLargerThanCap() async throws {
		StubURLProtocol.statusCode = 200
		StubURLProtocol.responseData = Data(repeating: 0x41, count: 50)
		do {
			_ = try await fetchRemoteData(from: url, label: "input", maxBytes: 10, session: stubbedSession())
			Issue.record("expected an error for an oversized response")
		} catch let error as MessageError {
			#expect(error.message.contains("exceeds"))
		}
	}

	@Test func acceptsResponseWithinCap() async throws {
		StubURLProtocol.statusCode = 200
		StubURLProtocol.responseData = Data(repeating: 0x41, count: 8)
		let data = try await fetchRemoteData(from: url, label: "input", maxBytes: 1000, session: stubbedSession())
		#expect(data.count == 8)
	}

	@Test func rejectsNon200Status() async throws {
		StubURLProtocol.statusCode = 404
		StubURLProtocol.responseData = Data("nope".utf8)
		do {
			_ = try await fetchRemoteData(from: url, label: "input", session: stubbedSession())
			Issue.record("expected an error for a non-200 status")
		} catch let error as MessageError {
			#expect(error.message.contains("404"))
		}
	}

	@Test func rejectsEmptyResponse() async throws {
		StubURLProtocol.statusCode = 200
		StubURLProtocol.responseData = Data()
		do {
			_ = try await fetchRemoteData(from: url, label: "input", session: stubbedSession())
			Issue.record("expected an error for an empty response")
		} catch let error as MessageError {
			#expect(error.message.contains("No data"))
		}
	}
}

/// Returns a canned HTTP response for any request. Configure via the static
/// properties before each call; the suite is serialized so they don't race.
final class StubURLProtocol: URLProtocol {
	// `nonisolated(unsafe)`: URLProtocol's registration API forces class-level
	// state; safe here because the suite is `.serialized` and each test sets
	// the values before issuing its single request.
	nonisolated(unsafe) static var statusCode = 200
	nonisolated(unsafe) static var responseData = Data()

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
	override func stopLoading() {}

	override func startLoading() {
		let response = HTTPURLResponse(
			url: request.url!,
			statusCode: Self.statusCode,
			httpVersion: "HTTP/1.1",
			headerFields: nil
		)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: Self.responseData)
		client?.urlProtocolDidFinishLoading(self)
	}
}
