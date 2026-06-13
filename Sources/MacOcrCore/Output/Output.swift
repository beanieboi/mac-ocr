import Foundation

/// Contract for result payloads that flow through `BatchRunner`. The output
/// strategy wraps each payload in a `ResultEnvelope` to add shared fields
/// (`source`, `page`, `pageCount`, `width`, `height`) before serializing.
/// `OCRResult` is the production conformer; tests inject synthetic payloads.
///
/// `Sendable` because payloads cross into the buffering actor behind
/// `OutputStrategy.analysis`.
public protocol ResultPayload: Encodable, Sendable {
	/// Text representation for `--format text`. Empty string is valid.
	var textOutput: String { get }
}

// MARK: - Encoders

/// Compact single-object JSON (no whitespace) — for JSONL streaming.
private let compactEncoder: JSONEncoder = {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.sortedKeys]
	return encoder
}()

/// Pretty-printed array JSON — for buffered `--format json` output.
private let prettyEncoder: JSONEncoder = {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
	return encoder
}()

func encodeJSONLine<Value: Encodable>(_ value: Value) throws -> String {
	let data = try compactEncoder.encode(value)
	return String(data: data, encoding: .utf8) ?? "{}"
}

func encodeJSONArray<Value: Encodable>(_ values: [Value]) throws -> String {
	let data = try prettyEncoder.encode(values)
	return String(data: data, encoding: .utf8) ?? "[]"
}
