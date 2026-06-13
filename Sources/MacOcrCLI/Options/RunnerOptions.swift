import Foundation
import MacOcrCore

/// Shared interface for the commands/option groups that accept image/PDF files
/// (`OcrCommandOptions` for the OCR command, and `SearchablePDFCommand`).
///
/// Provides default implementations for pdf-dpi validation, input-source
/// resolution, and resolved-DPI derivation, so each conformer only declares its
/// `@Argument`/`@Option` properties; the derived behaviour comes for free from
/// the protocol extension.
protocol RunnerOptions {
	var files: [String] { get }
	var pdfDpi: String { get }
	var roi: String? { get }
}

extension RunnerOptions {
	func validatePdfDpi() throws {
		try MacOcrCLI.validatePdfDpi(pdfDpi)
	}

	func resolveInputSources() -> [ImageSource] {
		resolveImageSources(files: files)
	}

	var resolvedPdfDpi: Int? {
		MacOcrCLI.resolvedPdfDpi(pdfDpi)
	}

	/// Parse `--roi`. Throwing (not `try?`): `validate()` already rejected
	/// malformed values, but if that invariant ever breaks, an invalid ROI
	/// must fail loudly rather than silently recognize the full image.
	func resolvedROI() throws -> BoundingBox? {
		guard let roi else { return nil }
		return try parseRegionOfInterest(roi)
	}
}
