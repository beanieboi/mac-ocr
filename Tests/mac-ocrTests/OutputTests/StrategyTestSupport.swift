import Foundation
import Testing

@testable import MacOcrCore

// MARK: - Toy payloads

struct AnalysisPayload: ResultPayload {
	let label: String
	var textOutput: String { label }
}

/// A payload whose `encode` always throws, used to verify that encoding errors
/// surface as thrown errors rather than silent empty-JSON fallbacks.
struct UnencodeablePayload: ResultPayload {
	struct EncodingError: Error {}
	var textOutput: String { "unencodeable" }
	func encode(to encoder: any Encoder) throws {
		throw EncodingError()
	}
}

// MARK: - Helper

func makeContext(page: Int, pageCount: Int) -> PageContext {
	let loader = ImageLoader(
		count: pageCount, sourcePath: nil,
		load: { _ in
			throw MessageError("not used in strategy test")
		})
	return PageContext(
		source: .file("/fixture.png"),
		page: page,
		pageCount: pageCount,
		loader: loader,
		width: 100,
		height: 100
	)
}

func makeContext(sourcePath: String, page: Int = 1, pageCount: Int = 1) -> PageContext {
	let loader = ImageLoader(
		count: pageCount, sourcePath: sourcePath,
		load: { _ in
			throw MessageError("not used in strategy test")
		})
	return PageContext(
		source: .file(sourcePath),
		page: page,
		pageCount: pageCount,
		loader: loader,
		width: 100,
		height: 100
	)
}
