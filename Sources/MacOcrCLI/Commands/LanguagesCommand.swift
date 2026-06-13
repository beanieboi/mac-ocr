import ArgumentParser
import MacOcrCore

/// Lists the recognition languages Vision supports on this macOS version. This
/// is a capability query, not an OCR action — and the languages apply to both
/// `ocr` and `searchable-pdf` — so it's a top-level subcommand rather than a
/// flag on `ocr`.
public struct LanguagesCommand: ParsableCommand {
	public static let configuration = CommandConfiguration(
		commandName: "languages",
		abstract: "List the recognition languages supported on this macOS version."
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
