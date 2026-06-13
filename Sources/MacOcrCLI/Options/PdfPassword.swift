import Foundation

/// Resolve the PDF password from the `--password` flag, falling back to the
/// `MAC_OCR_PDF_PASSWORD` environment variable. The flag wins; empty values are
/// treated as unset. The env var keeps the password out of `argv`, so it does
/// not leak into the process list or shell history.
func resolvePdfPassword(_ flagValue: String?) -> String? {
	if let flagValue, !flagValue.isEmpty {
		return flagValue
	}
	if let environment = ProcessInfo.processInfo.environment["MAC_OCR_PDF_PASSWORD"], !environment.isEmpty {
		return environment
	}
	return nil
}
