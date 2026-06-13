import Foundation
import Testing

/// Pins `--pdf-dpi auto` detection using the committed fixtures that were
/// authored for exactly this (see Tests/fixtures/README.md):
///
/// - `scanned-200dpi.pdf` — a 144×36 pt page embedding a 400×100 px image
///   (≈200 DPI source). Auto detection must render at ~200 DPI → 400×100 px,
///   not the 144-DPI floor (288×72 px).
/// - `scanned-form-xobject.pdf` — the same geometry, but the image is wrapped
///   in a Form XObject (Acrobat-OCR pattern); the detector must recurse.
/// - `huge-mediabox.pdf` — a 6000×6000 pt MediaBox that exceeds the 200 MP
///   render cap at 300 DPI and must fail cleanly.
@Suite(.serialized) struct PDFDPITests {

	private func firstPage(_ arguments: [String]) throws -> [String: Any] {
		let result = try TestSupport.run(arguments)
		#expect(result.exitCode == 0, "expected success; stderr: \(result.stderr)")
		let parsed = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
		return try #require(parsed as? [String: Any], "expected a JSONL object; got: \(result.stdout)")
	}

	@Test func autoDpiDetectsEmbeddedImageResolution() throws {
		let page = try firstPage([TestSupport.fixturePath("scanned-200dpi.pdf"), "--format", "jsonl"])
		// 144×36 pt page at the detected ~200 DPI → 400×100 px. The 144-DPI
		// floor fallback would render 288×72 and means detection regressed.
		#expect(page["width"] as? Int == 400)
		#expect(page["height"] as? Int == 100)
	}

	@Test func explicitDpiOverridesAutoDetection() throws {
		let page = try firstPage([
			TestSupport.fixturePath("scanned-200dpi.pdf"), "--format", "jsonl", "--pdf-dpi", "144",
		])
		#expect(page["width"] as? Int == 288)
		#expect(page["height"] as? Int == 72)
	}

	@Test func autoDpiRecursesIntoFormXObjects() throws {
		let page = try firstPage([TestSupport.fixturePath("scanned-form-xobject.pdf"), "--format", "jsonl"])
		// The page image hides inside a Form XObject; detection must recurse
		// (PDFDPIDetector.collectImageDimensions) instead of falling back to
		// the 144 floor.
		#expect(page["width"] as? Int == 400)
		#expect(page["height"] as? Int == 100)
	}

	@Test func hugeMediaBoxFailsCleanlyAtTheRenderCap() throws {
		let result = try TestSupport.run([
			TestSupport.fixturePath("huge-mediabox.pdf"), "--pdf-dpi", "300",
		])
		#expect(result.exitCode != 0)
		#expect(result.stderr.lowercased().contains("megapixel"), "stderr: \(result.stderr)")
	}
}
