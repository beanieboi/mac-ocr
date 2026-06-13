import Foundation

/// Cap on a remote (http/https) input. Remote inputs are buffered in memory to
/// sniff for PDF magic bytes and to feed Vision, so an unbounded download could
/// exhaust RAM. Honest oversized transfers are rejected with a clear message; a
/// runaway transfer is additionally bounded by the resource timeout below.
let maxRemoteInputBytes = 100 * 1024 * 1024

/// A URLSession configured for input downloads: explicit request and resource
/// timeouts instead of `URLSession.shared`'s default 60s request timeout / no
/// resource cap.
func makeRemoteInputSession() -> URLSession {
	let configuration = URLSessionConfiguration.ephemeral
	configuration.timeoutIntervalForRequest = 30
	configuration.timeoutIntervalForResource = 120
	return URLSession(configuration: configuration)
}

/// Download an http(s) input with explicit timeouts and a size cap, replacing
/// `URLSession.shared.data` (which has no size limit and only the default 60s
/// request timeout). Verifies the HTTP status and rejects empty or oversized
/// responses. `maxBytes`/`session` are injectable for testing.
func fetchRemoteData(
	from url: URL,
	label: String,
	maxBytes: Int = maxRemoteInputBytes,
	session: URLSession? = nil
) async throws -> Data {
	let ownsSession = session == nil
	let session = session ?? makeRemoteInputSession()
	defer { if ownsSession { session.finishTasksAndInvalidate() } }

	let (data, response) = try await session.data(from: url)

	if let http = response as? HTTPURLResponse, http.statusCode != 200 {
		throw MessageError("HTTP \(http.statusCode) for \(label)")
	}
	guard !data.isEmpty else {
		throw MessageError("No data received from \(label)")
	}
	guard data.count <= maxBytes else {
		let limit = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .binary)
		throw MessageError("\(label) exceeds the \(limit) limit for URL input. Download it and pass the local file instead.")
	}
	return data
}

/// Read all of standard input. Uses the throwing `readToEnd()` where available
/// so an I/O failure (e.g. a broken pipe feeding stdin) surfaces as a catchable
/// Swift error and a clean exit, rather than the uncatchable Objective-C
/// exception `readDataToEndOfFile()` raises.
func readAllStandardInput() throws -> Data {
	if #available(macOS 10.15.4, *) {
		return try FileHandle.standardInput.readToEnd() ?? Data()
	}
	return FileHandle.standardInput.readDataToEndOfFile()
}
