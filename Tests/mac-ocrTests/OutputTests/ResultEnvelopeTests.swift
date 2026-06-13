import Foundation
import Testing

@testable import MacOcrCore

// MARK: - Minimal test payloads

private struct TextPayload: ResultPayload {
	let text: String
	var textOutput: String { text }
}

private struct DimensionPayload: ResultPayload {
	let width: Int
	let height: Int
	var textOutput: String { "\(width)x\(height)" }
}

@Suite("ResultEnvelope")
struct ResultEnvelopeTests {

	// MARK: ResultEnvelope

	@Test func imageEnvelopeContainsCommonFields() throws {
		let envelope = ResultEnvelope(
			source: .file("/tmp/hello.png"),
			page: 2,
			pageCount: 3,
			width: 640,
			height: 480,
			payload: TextPayload(text: "Page Two")
		)

		let json = try encodeToDict(envelope)
		#expect(json["page"] as? Int == 2)
		#expect(json["pageCount"] as? Int == 3)
		#expect(json["width"] as? Int == 640)
		#expect(json["height"] as? Int == 480)
	}

	@Test func imageEnvelopeFlattensPayload() throws {
		let envelope = ResultEnvelope(
			source: .file("/tmp/hello.png"),
			page: 1,
			pageCount: 1,
			width: 400,
			height: 100,
			payload: TextPayload(text: "Hello World")
		)

		let json = try encodeToDict(envelope)
		// Payload key "text" should be at root level, not nested
		#expect(json["text"] as? String == "Hello World")
	}

	@Test func imageEnvelopeCommonDimensionsWinPayloadCollisions() throws {
		let envelope = ResultEnvelope(
			source: .file("/tmp/hello.png"),
			page: 1,
			pageCount: 1,
			width: 400,
			height: 100,
			payload: DimensionPayload(width: 64, height: 64)
		)

		let json = try encodeToDict(envelope)
		#expect(json["width"] as? Int == 400)
		#expect(json["height"] as? Int == 100)
	}

	@Test func imageEnvelopeDisplayLabelSinglePage() {
		let envelope = ResultEnvelope(
			source: .file("/tmp/hello.png"),
			page: 1,
			pageCount: 1,
			width: 400,
			height: 100,
			payload: TextPayload(text: "")
		)
		// Single-page: just the source displayName (full path for file sources)
		#expect(envelope.displayLabel == "/tmp/hello.png")
	}

	@Test func imageEnvelopeDisplayLabelMultiPage() {
		let envelope = ResultEnvelope(
			source: .file("/tmp/doc.pdf"),
			page: 2,
			pageCount: 3,
			width: 800,
			height: 1200,
			payload: TextPayload(text: "")
		)
		#expect(envelope.displayLabel == "/tmp/doc.pdf (page 2/3)")
	}
}

// MARK: - Helpers

private func encodeToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
	let data = try JSONEncoder().encode(value)
	return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}
