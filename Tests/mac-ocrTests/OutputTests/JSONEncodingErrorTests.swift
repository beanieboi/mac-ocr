import CoreGraphics
import Foundation
import Testing

@testable import MacOcrCore

@Suite("JSON encoding error propagation")
struct JSONEncodingErrorTests {

	@Test func encodeJSONLineThrowsOnEncodingFailure() {
		#expect(throws: (any Error).self) {
			_ = try encodeJSONLine(UnencodeablePayload())
		}
	}

	@Test func encodeJSONArrayThrowsOnEncodingFailure() {
		#expect(throws: (any Error).self) {
			_ = try encodeJSONArray([UnencodeablePayload()])
		}
	}

	@Test func jsonlStrategyPropagatesEncodingError() async throws {
		let strategy = try OutputStrategy<UnencodeablePayload>.analysis(
			format: .jsonl,
			outputMode: .off,
			totalSources: 1
		)
		let context = makeContext(page: 1, pageCount: 1)
		await #expect(throws: (any Error).self) {
			try await strategy.onResult(UnencodeablePayload(), context)
		}
	}

	@Test func jsonStrategyPropagatesEncodingErrorOnFinish() async throws {
		let strategy = try OutputStrategy<UnencodeablePayload>.analysis(
			format: .json,
			outputMode: .off,
			totalSources: 1
		)
		let context = makeContext(page: 1, pageCount: 1)
		// onResult buffers — does not throw yet
		try await strategy.onResult(UnencodeablePayload(), context)
		// onFinish flushes the buffer and must propagate the encoding error
		await #expect(throws: (any Error).self) {
			try await strategy.onFinish()
		}
	}
}
