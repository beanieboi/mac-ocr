import ArgumentParser
import Darwin
import Foundation
import MacOcrCore

public struct MacOcr: AsyncParsableCommand {
	public static let configuration = CommandConfiguration(
		commandName: "mac-ocr",
		abstract: "Recognize text in images and PDFs using Apple Vision.",
		discussion: """
			Pass one or more images or PDFs to recognize text. OCR is the default \
			action, so no subcommand is required:

			  mac-ocr receipt.jpg
			  mac-ocr page1.png page2.png --format jsonl
			  mac-ocr scan.pdf --format jsonl

			Use the `searchable-pdf` subcommand to render a PDF with an invisible, \
			selectable text layer over the original pages.
			""",
		version: macOcrVersion,
		subcommands: [
			OCRCommand.self,
			SearchablePDFCommand.self,
			LanguagesCommand.self,
		],
		defaultSubcommand: OCRCommand.self
	)

	public init() {}

	public static func run(arguments: [String]) async {
		await runParsedCommand(arguments)
	}
}

// Subcommand names known to this build. Used only to attribute machine-error
// envelopes to the right command. Derived at runtime from the configured
// subcommands so it never drifts out of sync.
private let knownSubcommands: Set<String> = {
	var names = Set(MacOcr.configuration.subcommands.map { $0._commandName })
	for subcommand in MacOcr.configuration.subcommands {
		for alias in subcommand.configuration.aliases {
			names.insert(alias)
		}
	}
	return names
}()

private func machineCommandName(_ arguments: [String]) -> String {
	arguments.first { knownSubcommands.contains($0) } ?? MacOcr.configuration.commandName ?? "mac-ocr"
}

private func runParsedCommand(_ arguments: [String]) async {
	let commandName = machineCommandName(arguments)
	do {
		var command = try MacOcr.parseAsRoot(arguments)
		if var asyncCommand = command as? AsyncParsableCommand {
			try await asyncCommand.run()
		} else {
			try command.run()
		}
	} catch let error as UsageError {
		MachineErrorReporter.report(
			kind: .usage,
			code: "usage_error",
			message: error.message,
			exitCode: 64,
			command: commandName
		)
		MacOcr.exit(withError: ValidationError(error.message))
	} catch let error as ValidationError {
		MachineErrorReporter.report(
			kind: .usage,
			code: "usage_error",
			message: error.message,
			exitCode: 64,
			command: commandName
		)
		MacOcr.exit(withError: error)
	} catch let error as BatchRunFailure {
		MachineErrorReporter.report(
			kind: .runtime,
			code: "batch_failed",
			message: "one or more inputs failed",
			exitCode: error.code,
			command: commandName
		)
		exit(error.code)
	} catch {
		// Includes ArgumentParser clean exits (--help/--version → no envelope,
		// exit 0) and parse/usage errors (real message, exit 64).
		MachineErrorReporter.reportThrownError(error, command: commandName)
		MacOcr.exit(withError: error)
	}
}
