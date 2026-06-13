import ArgumentParser
import Foundation
import MacOcrCore

/// The recognition flags shared verbatim by `ocr` and `searchable-pdf`.
/// Declared once so the two commands cannot drift; each command adds its own
/// surface on top (`--format`/`-o`/`--max-candidates` for ocr;
/// `-o`/`--ocr-all-pages` for searchable-pdf).
struct RecognitionOptions: ParsableArguments {
	@Flag(help: "Use fast recognition (lower accuracy).")
	var fast = false

	@Option(name: .long, help: "Password for an encrypted PDF (or set MAC_OCR_PDF_PASSWORD).")
	var password: String?

	@Option(name: .shortAndLong, help: "Recognition language (repeatable, BCP-47). Example: en-US")
	var language: [String] = []

	@Option(name: .shortAndLong, help: "Minimum confidence threshold (0.0–1.0).")
	var confidence: Float = 0.0

	@Option(name: [.customShort("w"), .long], help: "Custom vocabulary word (repeatable).")
	var customWords: [String] = []

	@Option(name: .long, help: "File with custom vocabulary words (one per line).")
	var customWordsFile: String?

	@Flag(name: .long, help: "Disable language correction.")
	var noLanguageCorrection = false

	@Option(name: .long, help: "Minimum text height relative to image (0.0–1.0).")
	var minTextHeight: Float?

	mutating func validate() throws {
		try confidence.requireUnitInterval(name: "--confidence")
		if let minTextHeight {
			try minTextHeight.requireUnitInterval(name: "--min-text-height")
		}
		if let customWordsFile {
			var isDirectory = ObjCBool(false)
			let exists = FileManager.default.fileExists(atPath: customWordsFile, isDirectory: &isDirectory)
			guard exists, !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: customWordsFile) else {
				throw ValidationError("Cannot read --custom-words-file: \(customWordsFile)")
			}
		}
		try validateLanguages()
	}

	/// Reject `-l` values Vision doesn't support — an unsupported language
	/// otherwise yields silently empty results. Matching is case-insensitive
	/// and rewrites entries to Vision's canonical casing (`en-us` → `en-US`).
	private mutating func validateLanguages() throws {
		guard !language.isEmpty else { return }
		let supported = supportedLanguages(fast: fast)
		let canonicalByLowercase = Dictionary(
			supported.map { ($0.lowercased(), $0) },
			uniquingKeysWith: { first, _ in first }
		)
		var unsupported: [String] = []
		language = language.map { entry in
			if let canonical = canonicalByLowercase[entry.lowercased()] {
				return canonical
			}
			unsupported.append(entry)
			return entry
		}
		guard unsupported.isEmpty else {
			let label = unsupported.count > 1 ? "languages" : "language"
			let listHint = fast ? "mac-ocr languages --fast" : "mac-ocr languages"
			throw ValidationError(
				"Unsupported recognition \(label): \(unsupported.joined(separator: ", ")). "
					+ "Run `\(listHint)` to list the languages available on this macOS version."
			)
		}
	}

	/// Build the core options. Per-command extras (`regionOfInterest`,
	/// `maxCandidates`) are passed in because they live on the commands.
	func buildOCROptions(regionOfInterest: BoundingBox?, maxCandidates: Int = 1) throws -> OCROptions {
		var allCustomWords = customWords
		if let filePath = customWordsFile {
			let content = try String(contentsOfFile: filePath, encoding: .utf8)
			let fileWords = content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
			allCustomWords.append(contentsOf: fileWords)
		}

		return OCROptions(
			recognitionLevel: fast ? .fast : .accurate,
			languages: language,
			usesLanguageCorrection: !noLanguageCorrection,
			customWords: allCustomWords,
			minimumTextHeight: minTextHeight,
			minimumConfidence: confidence,
			regionOfInterest: regionOfInterest,
			maxCandidates: maxCandidates
		)
	}
}
