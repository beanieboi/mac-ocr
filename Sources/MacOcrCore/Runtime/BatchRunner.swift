import Foundation

/// Runner for per-image/per-page analysis: owns source iteration, page
/// loading, session construction, and error aggregation via `ErrorSink`.
/// Output formatting and destination are fully delegated to the injected
/// `OutputStrategy`; the per-page operation itself is the injected `runPage`
/// closure (the `ocr` command passes `OCREngine.run`).
///
/// ## Serial iteration is mandatory
///
/// Vision request execution is serialized through `VisionRuntime` to avoid GCD
/// dispatch-pool exhaustion at high concurrency (see `VisionRuntime` for the
/// full rationale). Vision also parallelizes internally across cores, so
/// serial dispatch already saturates the hardware.
public enum BatchRunner {

	/// Run `runPage` serially over every page of every source. Each page's
	/// result is forwarded to `output.onResult`; after each source's pages
	/// finish, `output.onSourceDone` is called; after all sources finish,
	/// `output.onFinish` is called.
	///
	/// `onProgress` fires once per page attempt (success or failure) with the
	/// 0-based source index and 1-based page number, on the calling task —
	/// the CLI drives its live counter from it.
	///
	/// Per-source and per-page errors are reported to `stderr` via `ErrorSink`
	/// and accumulated; the run throws `BatchRunFailure` if any error occurred.
	public static func run<Result>(
		sources: [ImageSource],
		output: OutputStrategy<Result>,
		resolvedPdfDpi: Int? = nil,
		pdfPassword: String? = nil,
		onProgress: ((_ sourceIndex: Int, _ source: ImageSource, _ page: Int, _ pageCount: Int) -> Void)? = nil,
		runPage: (VisionSession) async throws -> Result
	) async throws {
		guard !sources.isEmpty else { return }

		let errorSink = ErrorSink()

		for (sourceIndex, source) in sources.enumerated() {
			let loader: ImageLoader
			do {
				loader = try await openSource(source, pdfDpi: resolvedPdfDpi, pdfPassword: pdfPassword)
			} catch {
				await errorSink.report(error)
				continue
			}

			for pageIndex in 0..<loader.count {
				do {
					let loaded = try loader.load(pageIndex)
					let session = VisionSession(image: loaded.image, orientation: loaded.orientation)
					let result = try await runPage(session)
					let context = PageContext(
						source: source,
						page: pageIndex + 1,
						pageCount: loader.count,
						loader: loader,
						width: loaded.displayWidth,
						height: loaded.displayHeight
					)
					try await output.onResult(result, context)
				} catch {
					await errorSink.report(error)
				}
				onProgress?(sourceIndex, source, pageIndex + 1, loader.count)
				await Task.yield()
			}

			do {
				try await output.onSourceDone(source, loader)
			} catch {
				await errorSink.report(error)
			}
		}

		do {
			try await output.onFinish()
		} catch {
			await errorSink.report(error)
		}

		if await errorSink.hadError {
			throw BatchRunFailure()
		}
	}
}

// MARK: - PageContext

/// Per-page metadata passed to `OutputStrategy.onResult`. Bundles all
/// information the strategy needs to build an envelope, write a file, or
/// print a header.
public struct PageContext: Sendable {
	public let source: ImageSource
	public let page: Int
	public let pageCount: Int
	/// Provides `sourcePath` for `--output` file output.
	public let loader: ImageLoader
	public let width: Int
	public let height: Int
}

// MARK: - OutputStrategy

/// Encapsulates output behavior for `BatchRunner.run`. The runner calls
/// `onResult` for each per-page result, `onSourceDone` after each source's
/// pages, and `onFinish` once after the last source.
///
/// `OutputStrategy.analysis(...)` builds the ready-made text/json/jsonl
/// strategy; tests may construct strategies directly via this initializer
/// with synthetic payloads.
public struct OutputStrategy<Result> {
	/// Called once per page result.
	public let onResult: (Result, PageContext) async throws -> Void
	/// Called once per source after its page loop. Used by write-mode
	/// strategies to flush the per-source buffer.
	public let onSourceDone: (ImageSource, ImageLoader) async throws -> Void
	/// Called once after all sources are processed. Used by buffered
	/// strategies (e.g. `--format json`) to flush accumulated output.
	public let onFinish: () async throws -> Void

	public init(
		onResult: @escaping (Result, PageContext) async throws -> Void,
		onSourceDone: @escaping (ImageSource, ImageLoader) async throws -> Void = { _, _ in },
		onFinish: @escaping () async throws -> Void = {}
	) {
		self.onResult = onResult
		self.onSourceDone = onSourceDone
		self.onFinish = onFinish
	}
}
