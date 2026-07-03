import ArgumentParser
import MacOcrCore

/// Lists the recognition languages Vision supports on this macOS version. This
/// is a capability query, not an OCR action — and the languages apply to both
/// `ocr` and `searchable-pdf` — so it's a top-level subcommand rather than a
/// flag on `ocr`.
public struct LanguagesCommand: ParsableCommand {
	public static let configuration = CommandConfiguration(
		commandName: "languages",
		abstract: "List the recognition languages supported on this macOS version.",
		discussion: """
			Prints one BCP-47 language code per line. Pass the codes to `ocr` or \
			`searchable-pdf` via -l/--language.

			# Languages for the default (accurate) recognizer
			mac-ocr languages

			# Languages available to --fast
			mac-ocr languages --fast
			"""
	)

	public init() {}

	@Flag(help: "List the languages available to fast recognition.")
	var fast = false

	public func run() throws {
		for language in supportedLanguages(fast: fast) {
			print(language)
		}
	}
}
