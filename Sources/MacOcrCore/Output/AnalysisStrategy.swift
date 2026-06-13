import Foundation

/// Factory for the text/json/jsonl output strategy.
extension OutputStrategy where Result: ResultPayload {

	/// Creates a strategy that handles text/json/jsonl formatting and optional
	/// file output via `--output` / `-o`.
	///
	/// - Parameters:
	///   - format: Output format (text, json, jsonl).
	///   - outputMode: If non-`.off`, results are written to files rather than stdout.
	///   - totalSources: Total source count — used to reject multi-source `.static`
	///     and to gate multi-source text headers (`==> path <==`).
	public static func analysis(
		format: OutputFormat,
		outputMode: OutputMode,
		totalSources: Int
	) throws -> OutputStrategy<Result> {
		if case .static = outputMode, totalSources > 1 {
			throw UsageError("-o / --output with a fixed path cannot be used with multiple sources — use a directory or a template for batch output")
		}

		let state = AnalysisStrategyState<Result>(
			format: format,
			outputMode: outputMode,
			hasMultipleSources: totalSources > 1
		)
		return OutputStrategy(
			onResult: { result, context in
				try await state.processResult(result: result, context: context)
			},
			onSourceDone: { _, loader in
				try await state.flushWriteBuffer(loader: loader)
			},
			onFinish: {
				try await state.flushJsonBuffer()
			}
		)
	}
}

// MARK: - State

private actor AnalysisStrategyState<Result: ResultPayload> {
	let format: OutputFormat
	let outputMode: OutputMode
	let hasMultipleSources: Bool
	var firstEmit = true
	var jsonBuffer: [ResultEnvelope<Result>] = []
	var writeBuffer: [ResultEnvelope<Result>] = []
	var writtenPaths: Set<String> = []

	init(format: OutputFormat, outputMode: OutputMode, hasMultipleSources: Bool) {
		self.format = format
		self.outputMode = outputMode
		self.hasMultipleSources = hasMultipleSources
	}

	func processResult(result: Result, context: PageContext) throws {
		let envelope = ResultEnvelope(
			source: context.source,
			page: context.page,
			pageCount: context.pageCount,
			width: context.width,
			height: context.height,
			payload: result
		)

		if case .off = outputMode {
			// stdout path
		} else {
			writeBuffer.append(envelope)
			return
		}

		let showHeaders = hasMultipleSources || context.pageCount > 1
		switch format {
		case .text:
			if showHeaders {
				if !firstEmit { print("") }
				print("==> \(envelope.displayLabel) <==")
			}
			let text = result.textOutput
			if !text.isEmpty {
				print(text)
			}
			firstEmit = false
		case .jsonl:
			print(try encodeJSONLine(envelope))
		case .json:
			jsonBuffer.append(envelope)
		}
	}

	func flushWriteBuffer(loader: ImageLoader) throws {
		guard !writeBuffer.isEmpty else { return }
		let envelopes = writeBuffer
		writeBuffer = []
		let files = try resolveAnalysisOutputFiles(
			loader: loader,
			envelopes: envelopes,
			format: format,
			outputMode: outputMode
		)
		var batchPaths: Set<String> = []
		for file in files {
			if writtenPaths.contains(file.path) || batchPaths.contains(file.path) {
				throw MessageError(
					"Output template produces the same path '\(file.path)' for multiple inputs. "
						+ "Include per-input placeholders like [name] or [page] to differentiate outputs."
				)
			}
			batchPaths.insert(file.path)
		}
		try writeOutputFiles(files)
		writtenPaths.formUnion(batchPaths)
	}

	func flushJsonBuffer() throws {
		guard !jsonBuffer.isEmpty else {
			// A JSON consumer expects valid JSON on stdout even when nothing was
			// recognized (e.g. every input failed). Emit an empty array rather
			// than no output. Only for stdout json mode — text/jsonl emit
			// per-result, and file mode routes through the write buffer.
			if format == .json, case .off = outputMode {
				print("[]")
			}
			return
		}
		print(try encodeJSONArray(jsonBuffer))
		jsonBuffer = []
	}
}

// MARK: - Write helpers

struct OutputFile {
	let path: String
	let content: String
}

/// Resolve per-source output files without writing them.
///
/// Per-page template mode emits one file per page; consolidated mode emits one
/// file per source. Either way, every emitted path is returned so the caller
/// can detect collisions across sources (e.g., `a/report.pdf` and `b/report.pdf`
/// both expanding `[name]-[page]` to the same path).
func resolveAnalysisOutputFiles<Payload: ResultPayload>(
	loader: ImageLoader,
	envelopes: [ResultEnvelope<Payload>],
	format: OutputFormat,
	outputMode: OutputMode
) throws -> [OutputFile] {
	let fileExtension: String
	switch format {
	case .json: fileExtension = ".json"
	case .jsonl: fileExtension = ".jsonl"
	case .text: fileExtension = ".txt"
	}

	// When the output template explicitly references the [page] placeholder,
	// the user wants one file per page rather than all pages consolidated into
	// one file. Emit each envelope to its own path in that case.
	if case .template(let template) = outputMode, template.referencesPageNumber {
		var files: [OutputFile] = []
		for envelope in envelopes {
			let outputPath = try resolveOutputPath(
				mode: outputMode,
				sourcePath: loader.sourcePath,
				page: envelope.page,
				pageCount: envelope.pageCount,
				outputExtension: fileExtension
			)
			let content: String
			switch format {
			case .json:
				content = try encodeJSONArray([envelope]) + "\n"
			case .jsonl:
				content = try encodeJSONLine(envelope) + "\n"
			case .text:
				let text = envelope.payload.textOutput
				content = text.isEmpty ? "" : text + "\n"
			}
			files.append(OutputFile(path: outputPath, content: content))
		}
		return files
	}

	// Default: all pages of one source are written into a single file.
	//
	// For directory/static modes, pass pageCount = 1 so that
	// resolveOutputPath never appends a page number to the filename —
	// the result is always `source.txt` / `source.json` regardless of how
	// many pages the source has.
	//
	// For template mode without [page], pass the actual pageCount so that
	// [pagecount] renders as the real total (e.g. 3), not "1".
	let consolidatedPageCount: Int
	if case .template = outputMode {
		consolidatedPageCount = envelopes.first?.pageCount ?? 1
	} else {
		consolidatedPageCount = 1
	}
	let outputPath = try resolveOutputPath(
		mode: outputMode,
		sourcePath: loader.sourcePath,
		page: 1,
		pageCount: consolidatedPageCount,
		outputExtension: fileExtension
	)

	let content: String
	switch format {
	case .json:
		content = try encodeJSONArray(envelopes) + "\n"
	case .jsonl:
		content = try envelopes.map { try encodeJSONLine($0) }.joined(separator: "\n") + "\n"
	case .text:
		content = envelopes.map(\.payload.textOutput).joined(separator: "\n") + "\n"
	}

	return [OutputFile(path: outputPath, content: content)]
}

func writeOutputFiles(_ files: [OutputFile]) throws {
	for file in files {
		try ensureParentDirectory(forFile: file.path)
		try file.content.write(toFile: file.path, atomically: true, encoding: .utf8)
	}
}
