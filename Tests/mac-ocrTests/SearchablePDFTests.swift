import Foundation
import PDFKit
import Testing

@testable import MacOcrCore

@Suite(.serialized) struct SearchablePDFTests {
	private static let fixtures = EngineTestSupport.fixturesURL

	private static func source(_ name: String) -> ImageSource {
		.file(fixtures.appendingPathComponent(name).path)
	}

	private func render(_ name: String, pdfDpi: Int? = nil) async throws -> PDFDocument {
		let data = try await SearchablePDF.render(
			source: Self.source(name),
			options: OCROptions(),
			pdfDpi: pdfDpi
		)
		guard let document = PDFDocument(data: data) else {
			throw MessageError("output was not a valid PDF")
		}
		return document
	}

	private func text(_ document: PDFDocument) -> String {
		(document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
	}

	@Test func imageBecomesOnePageWithSelectableText() async throws {
		let document = try await render("hello.png")
		#expect(document.pageCount == 1)
		#expect(text(document).contains("Hello World"))
	}

	@Test func pdfPreservesPageCountAndText() async throws {
		let document = try await render("multipage.pdf")
		#expect(document.pageCount == 3)
		let extracted = text(document)
		#expect(extracted.contains("Page One"))
		#expect(extracted.contains("Page Two"))
		#expect(extracted.contains("Page Three"))
	}

	@Test func pdfPagesStayInOrder() async throws {
		// Each scanned page's recognized text must land on its own page, in
		// order. Guards the render/OCR pipeline against shuffling pages when
		// rendering runs ahead of recognition on a background task.
		let document = try await render("multipage.pdf")
		#expect(document.pageCount == 3)
		let perPage = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
		#expect(perPage[0].contains("Page One"))
		#expect(perPage[1].contains("Page Two"))
		#expect(perPage[2].contains("Page Three"))
	}

	@Test func recognizedWordsExtractAsCleanRuns() async throws {
		// Regression: a non-unit horizontal text scale once made extractors read
		// "Hello" as "H e l l o", breaking search. Assert contiguous words survive.
		let document = try await render("document-photo.png")
		#expect(text(document).contains("Hello World"))
	}

	@Test func invisibleTextIsPositionedPerWord() async throws {
		// The invisible layer draws one run per word at Vision's per-word box,
		// so selecting "World" must land to the right of "Hello" rather than
		// both starting at the line origin (the old line-level behavior).
		let document = try await render("hello.png")
		let page = try #require(document.page(at: 0))

		func selectionBounds(_ word: String) throws -> CGRect {
			let selections = document.findString(word, withOptions: [])
			let selection = try #require(selections.first, "expected '\(word)' to be findable")
			return selection.bounds(for: page)
		}

		let hello = try selectionBounds("Hello")
		let world = try selectionBounds("World")
		#expect(
			world.minX > hello.minX + hello.width * 0.5,
			"'World' selection must start past 'Hello' (per-word geometry); hello: \(hello), world: \(world)"
		)
		// Each word's run is narrower than the whole line.
		let line = hello.union(world)
		#expect(hello.width < line.width)
		#expect(world.width < line.width)
	}

	@Test func emptyImageProducesPageWithoutText() async throws {
		let document = try await render("empty.png")
		#expect(document.pageCount == 1)
		#expect(text(document).isEmpty)
	}

	@Test func imagePageIsSizedToPixelDimensions() async throws {
		// Image inputs use 1px = 1pt page sizing; hello.png is 400×100.
		let document = try await render("hello.png")
		let bounds = try #require(document.page(at: 0)).bounds(for: .mediaBox)
		#expect(Int(bounds.width) == 400)
		#expect(Int(bounds.height) == 100)
	}
}
