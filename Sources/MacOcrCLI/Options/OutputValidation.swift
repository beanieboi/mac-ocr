import ArgumentParser
import Foundation
import MacOcrCore

func validateOutputModeSupportsSources(_ outputMode: OutputMode, files: [String]) throws {
	let hasStdinInput = files.contains("-") || (files.isEmpty && !FileHandle.standardInput.isTerminal)
	switch outputMode {
	case .off, .static:
		return

	case .directory:
		if hasStdinInput {
			throw ValidationError("--output cannot be used with stdin input")
		}
		try validateURLFilenames(files: files, outputDescription: "directory output")

	case .template(let template):
		if hasStdinInput, template.referencesSourceFilename {
			throw ValidationError(
				"Output template cannot use [name] or [ext] with stdin input. "
					+ "Use a fixed -o <file> path or a template without source filename placeholders."
			)
		}
		if template.referencesSourceFilename {
			try validateURLFilenames(files: files, outputDescription: "this output template")
		}
	}
}

private func validateURLFilenames(files: [String], outputDescription: String) throws {
	for file in files where isURLArgument(file) && urlOutputFilename(from: file) == nil {
		throw ValidationError(
			"URL input does not have a filename for \(outputDescription): \(file). " + "Use -o <file> for a fixed output path."
		)
	}
}
