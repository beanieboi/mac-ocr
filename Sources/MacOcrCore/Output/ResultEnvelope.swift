import Foundation

/// Per-page result envelope emitted by the `ocr` output strategy.
///
/// Encodes as a flat JSON object with shared fields at the top level and
/// payload keys merged in:
///
///     {
///       "source": { "type": "file", "path": "…" },
///       "page": 1,
///       "pageCount": 1,
///       "width": 400,
///       "height": 100,
///       // … payload keys …
///     }
struct ResultEnvelope<Payload: ResultPayload>: Encodable {
	let source: ImageSource
	let page: Int
	let pageCount: Int
	let width: Int
	let height: Int
	let payload: Payload

	private enum CommonKeys: String, CodingKey {
		case source, page, pageCount, width, height
	}

	func encode(to encoder: Encoder) throws {
		try payload.encode(to: encoder)
		var container = encoder.container(keyedBy: CommonKeys.self)
		try container.encode(source, forKey: .source)
		try container.encode(page, forKey: .page)
		try container.encode(pageCount, forKey: .pageCount)
		try container.encode(width, forKey: .width)
		try container.encode(height, forKey: .height)
	}

	/// Display label for text-mode headers: `doc.pdf (page 1/3)` for multi-
	/// page sources, `doc.pdf` otherwise.
	var displayLabel: String {
		let base = source.displayName
		if pageCount > 1 {
			return "\(base) (page \(page)/\(pageCount))"
		}
		return base
	}
}
