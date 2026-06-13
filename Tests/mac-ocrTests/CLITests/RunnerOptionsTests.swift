import Foundation
import Testing

@testable import MacOcrCLI

// Compile-time conformance check: if any type loses RunnerOptions conformance, this won't build.
private func _assertConforms<T: RunnerOptions>(_: T.Type) {}
private func _conformanceCheck() {
	_assertConforms(OcrCommandOptions.self)
	_assertConforms(SearchablePDFCommand.self)
}

@Suite("RunnerOptions")
struct RunnerOptionsTests {

	// MARK: validatePdfDpi

	@Test func validateAcceptsAuto() throws {
		var options = OcrCommandOptions()
		options.pdfDpi = "auto"
		#expect(throws: Never.self) { try options.validatePdfDpi() }
	}

	@Test func validateAcceptsIntegerInRange() throws {
		var options = OcrCommandOptions()
		options.pdfDpi = "144"
		#expect(throws: Never.self) { try options.validatePdfDpi() }
	}

	@Test func validateRejectsOutOfRangeInteger() {
		var options = OcrCommandOptions()
		options.pdfDpi = "9999"
		#expect(throws: Error.self) { try options.validatePdfDpi() }
	}

	@Test func validateRejectsNonNumeric() {
		var options = OcrCommandOptions()
		options.pdfDpi = "fast"
		#expect(throws: Error.self) { try options.validatePdfDpi() }
	}

	// MARK: resolvedPdfDpi

	@Test func resolvedPdfDpiAutoReturnsNil() {
		var options = OcrCommandOptions()
		options.pdfDpi = "auto"
		#expect(options.resolvedPdfDpi == nil)
	}

	@Test func resolvedPdfDpiIntegerReturnsValue() {
		var options = OcrCommandOptions()
		options.pdfDpi = "300"
		#expect(options.resolvedPdfDpi == 300)
	}

	// MARK: resolveInputSources

	@Test func resolveInputSourcesMapsFilePaths() {
		var options = OcrCommandOptions()
		options.files = ["/tmp/a.png", "/tmp/b.jpg"]
		let sources = options.resolveInputSources()
		#expect(sources == [.file("/tmp/a.png"), .file("/tmp/b.jpg")])
	}

	@Test func resolveInputSourcesPreservesOrder() {
		var options = OcrCommandOptions()
		options.files = ["/tmp/first.png", "/tmp/second.png", "/tmp/third.png"]
		let sources = options.resolveInputSources()
		#expect(sources == [.file("/tmp/first.png"), .file("/tmp/second.png"), .file("/tmp/third.png")])
	}
}
