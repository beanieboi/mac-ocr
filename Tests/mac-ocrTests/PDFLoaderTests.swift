import Foundation
import Testing

@Suite(.serialized) struct PDFLoaderTests {

	// MARK: - Invalid MediaBox

	/// `invalid-mediabox.pdf` has a valid 1-page PDF structure whose MediaBox is
	/// [0 0 0 100] — zero width. After successful document load the renderer
	/// catches widthPixels == 0 and throws "PDF page N has invalid dimensions".
	@Test func invalidMediaBoxExitsNonZero() throws {
		let result = try TestSupport.run([
			"ocr",
			TestSupport.fixturePath("invalid-mediabox.pdf"),
		])
		#expect(result.exitCode != 0)
	}

	@Test func invalidMediaBoxPrintsInvalidDimensionsError() throws {
		let result = try TestSupport.run([
			"ocr",
			TestSupport.fixturePath("invalid-mediabox.pdf"),
		])
		#expect(
			result.stderr.contains("invalid dimensions") || result.stderr.contains("invalid dimension"),
			"Expected 'invalid dimensions' in stderr; got: \(result.stderr)"
		)
	}

	@Test func invalidMediaBoxErrorMentionsPageNumber() throws {
		let result = try TestSupport.run([
			"ocr",
			TestSupport.fixturePath("invalid-mediabox.pdf"),
		])
		// The error message includes the page index: "PDF page 1 has invalid dimensions"
		#expect(
			result.stderr.contains("page"),
			"Expected page reference in error message; got: \(result.stderr)"
		)
	}

	// MARK: - Corrupt / non-loadable PDF

	/// A PDF header with no valid object table causes CGPDFDocument to return nil,
	/// exercising the "Cannot read PDF" guard in openPDFFromFile.
	@Test func corruptPDFExitsNonZero() throws {
		// Write a file starting with %PDF- but without any valid structure
		let tempPath = NSTemporaryDirectory() + "mac-ocr-corrupt-\(UUID().uuidString).pdf"
		defer { try? FileManager.default.removeItem(atPath: tempPath) }
		try "%PDF-1.4\n% this is not a valid pdf".write(toFile: tempPath, atomically: true, encoding: .utf8)

		let result = try TestSupport.run(["ocr", tempPath])
		#expect(result.exitCode != 0)
	}

	@Test func corruptPDFPrintsCannotReadError() throws {
		let tempPath = NSTemporaryDirectory() + "mac-ocr-corrupt2-\(UUID().uuidString).pdf"
		defer { try? FileManager.default.removeItem(atPath: tempPath) }
		try "%PDF-1.4\n% truncated".write(toFile: tempPath, atomically: true, encoding: .utf8)

		let result = try TestSupport.run(["ocr", tempPath])
		#expect(
			result.stderr.contains("Cannot read PDF") || result.stderr.contains("cannot read"),
			"Expected 'Cannot read PDF' in stderr; got: \(result.stderr)"
		)
	}

	// MARK: - Zero-page PDFs

	/// CGPDFDocument returns nil when /Pages /Count is 0, so the "Cannot read PDF"
	/// guard fires. This test asserts the process exits non-zero with a meaningful
	/// error rather than crashing.
	@Test func zeroPagePDFExitsNonZeroWithError() throws {
		// Construct a zero-page PDF (valid structure, /Count 0).
		// CoreGraphics rejects it and returns nil from CGPDFDocument.
		let pdf = buildZeroPagePDF()
		let tempPath = NSTemporaryDirectory() + "mac-ocr-zero-page-\(UUID().uuidString).pdf"
		defer { try? FileManager.default.removeItem(atPath: tempPath) }
		try pdf.write(to: URL(fileURLWithPath: tempPath))

		let result = try TestSupport.run(["ocr", tempPath])
		#expect(result.exitCode != 0)
		#expect(!result.stderr.isEmpty, "Expected an error message in stderr")
	}

	// MARK: - Oversized render guard

	/// A 1-page PDF with an enormous MediaBox. At 600 DPI the pixel product
	/// overflows what the diagnostic `Int64(...)` conversion (and the later
	/// `Int(widthPixels)` casts) can represent, which traps the process instead
	/// of throwing. The renderer must reject it with a friendly megapixel error.
	@Test func giganticMediaBoxThrowsInsteadOfTrapping() throws {
		let pdf = buildSinglePagePDF(mediaBox: "0 0 400000000 400000000")
		let tempPath = NSTemporaryDirectory() + "mac-ocr-giant-\(UUID().uuidString).pdf"
		defer { try? FileManager.default.removeItem(atPath: tempPath) }
		try pdf.write(to: URL(fileURLWithPath: tempPath))

		let result = try TestSupport.run(["ocr", "--pdf-dpi", "600", tempPath])
		#expect(result.exitCode == 1, "Expected clean exit 1, got \(result.exitCode); stderr: \(result.stderr)")
		#expect(
			result.stderr.contains("megapixel"),
			"Expected a friendly megapixel error rather than a crash; got: \(result.stderr)"
		)
	}

	/// With `--pdf-dpi auto` (the default), the source-DPI detector divides an
	/// image XObject's pixel dimensions by the page size in inches. A sub-point
	/// MediaBox with an enormous declared image makes that ratio exceed Int.max,
	/// trapping the `Int(...)` conversion before the renderer's guards run. The
	/// detector must clamp/guard and the page must surface a normal PDF error.
	@Test func autoDpiTinyMediaBoxWithImageThrowsInsteadOfTrapping() throws {
		let pdf = buildSinglePageImagePDF(
			mediaBox: "0 0 0.001 0.001",
			imageWidth: 1_000_000_000_000_000,
			imageHeight: 1_000_000_000_000_000
		)
		let tempPath = NSTemporaryDirectory() + "mac-ocr-autodpi-\(UUID().uuidString).pdf"
		defer { try? FileManager.default.removeItem(atPath: tempPath) }
		try pdf.write(to: URL(fileURLWithPath: tempPath))

		// No --pdf-dpi: exercises the auto-detect path.
		let result = try TestSupport.run(["ocr", tempPath])
		#expect(result.exitCode == 1, "Expected clean exit 1, got \(result.exitCode); stderr: \(result.stderr)")
		#expect(
			!result.stderr.contains("Fatal error"),
			"Process trapped instead of erroring cleanly; got: \(result.stderr)"
		)
	}

	// MARK: - Helpers

	/// Returns a syntactically valid PDF Data object whose /Pages /Count is 0.
	/// CGPDFDocument returns nil for such documents, so the "Cannot read PDF"
	/// guard fires and the process exits non-zero with a meaningful error.
	private func buildZeroPagePDF() -> Data {
		var content = Data("%PDF-1.4\n".utf8)

		let obj1Offset = content.count
		content.append(contentsOf: "1 0 obj\n<</Type /Catalog /Pages 2 0 R>>\nendobj\n".utf8)

		let obj2Offset = content.count
		content.append(contentsOf: "2 0 obj\n<</Type /Pages /Kids [] /Count 0>>\nendobj\n".utf8)

		let xrefOffset = content.count
		content.append(contentsOf: "xref\n0 3\n".utf8)
		content.append(contentsOf: "0000000000 65535 f\r\n".utf8)
		content.append(contentsOf: String(format: "%010d 00000 n\r\n", obj1Offset).utf8)
		content.append(contentsOf: String(format: "%010d 00000 n\r\n", obj2Offset).utf8)
		content.append(contentsOf: "trailer\n<</Size 3 /Root 1 0 R>>\n".utf8)
		content.append(contentsOf: "startxref\n\(xrefOffset)\n%%EOF\n".utf8)

		return content
	}

	/// Returns a syntactically valid 1-page PDF with the given MediaBox (a raw
	/// PDF array body like "0 0 400000000 400000000"). Used to exercise the
	/// renderer's oversized-dimension guards with exact, faithfully
	/// round-tripped values.
	private func buildSinglePagePDF(mediaBox: String) -> Data {
		var content = Data("%PDF-1.4\n".utf8)

		let obj1Offset = content.count
		content.append(contentsOf: "1 0 obj\n<</Type /Catalog /Pages 2 0 R>>\nendobj\n".utf8)

		let obj2Offset = content.count
		content.append(contentsOf: "2 0 obj\n<</Type /Pages /Kids [3 0 R] /Count 1>>\nendobj\n".utf8)

		let obj3Offset = content.count
		content.append(contentsOf: "3 0 obj\n<</Type /Page /Parent 2 0 R /MediaBox [\(mediaBox)]>>\nendobj\n".utf8)

		let xrefOffset = content.count
		content.append(contentsOf: "xref\n0 4\n".utf8)
		content.append(contentsOf: "0000000000 65535 f\r\n".utf8)
		content.append(contentsOf: String(format: "%010d 00000 n\r\n", obj1Offset).utf8)
		content.append(contentsOf: String(format: "%010d 00000 n\r\n", obj2Offset).utf8)
		content.append(contentsOf: String(format: "%010d 00000 n\r\n", obj3Offset).utf8)
		content.append(contentsOf: "trailer\n<</Size 4 /Root 1 0 R>>\n".utf8)
		content.append(contentsOf: "startxref\n\(xrefOffset)\n%%EOF\n".utf8)

		return content
	}

	/// Returns a valid 1-page PDF whose page references one Image XObject with
	/// the given declared pixel dimensions. The image stream is a single junk
	/// byte — the DPI detector only reads `/Width` and `/Height`, never decodes
	/// pixels — which lets a test declare absurd dimensions to drive the
	/// detector's pixels-per-inch math.
	private func buildSinglePageImagePDF(mediaBox: String, imageWidth: Int, imageHeight: Int) -> Data {
		var content = Data("%PDF-1.4\n".utf8)
		var offsets: [Int] = []

		offsets.append(content.count)
		content.append(contentsOf: "1 0 obj\n<</Type /Catalog /Pages 2 0 R>>\nendobj\n".utf8)

		offsets.append(content.count)
		content.append(contentsOf: "2 0 obj\n<</Type /Pages /Kids [3 0 R] /Count 1>>\nendobj\n".utf8)

		offsets.append(content.count)
		content.append(contentsOf: "3 0 obj\n<</Type /Page /Parent 2 0 R /MediaBox [\(mediaBox)] /Resources <</XObject <</Im0 4 0 R>>>>>>\nendobj\n".utf8)

		offsets.append(content.count)
		content.append(
			contentsOf:
				"4 0 obj\n<</Type /XObject /Subtype /Image /Width \(imageWidth) /Height \(imageHeight) /BitsPerComponent 8 /ColorSpace /DeviceGray /Length 1>>\nstream\n"
				.utf8)
		content.append(0x00)
		content.append(contentsOf: "\nendstream\nendobj\n".utf8)

		let xrefOffset = content.count
		content.append(contentsOf: "xref\n0 5\n".utf8)
		content.append(contentsOf: "0000000000 65535 f\r\n".utf8)
		for offset in offsets {
			content.append(contentsOf: String(format: "%010d 00000 n\r\n", offset).utf8)
		}
		content.append(contentsOf: "trailer\n<</Size 5 /Root 1 0 R>>\n".utf8)
		content.append(contentsOf: "startxref\n\(xrefOffset)\n%%EOF\n".utf8)

		return content
	}
}
