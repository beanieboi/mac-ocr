import Foundation

/// Centralized error reporter for runner invocations.
///
/// `BatchRunner` creates one `ErrorSink`
/// per invocation, reports errors through it during source iteration, and
/// checks `hadError` at the end to determine the exit code.
///
/// Using an actor (rather than global mutable state) keeps error reporting
/// thread-safe without locks, and makes per-invocation state explicit.
///
/// Usage in a runner:
///
///     let sink = ErrorSink()
///     for source in sources {
///         do { try await process(source) }
///         catch { await sink.report(error) }
///     }
///     if await sink.hadError { throw BatchRunFailure() }
///
public actor ErrorSink {
	/// Whether at least one error has been reported in this invocation.
	public private(set) var hadError = false

	public init() {}

	/// Write `error.localizedDescription` to stderr and set `hadError`.
	public func report(_ error: Error) {
		report(error.localizedDescription)
	}

	/// Write a plain message to stderr and set `hadError`.
	public func report(_ message: String) {
		// On an interactive terminal a transient progress counter may occupy
		// the current line; return to column 0 and clear it so the error
		// never appends to the counter. No-op when the cursor is already at
		// the start of a fresh line.
		if isatty(STDERR_FILENO) != 0 {
			fputs("\r\u{1b}[K", stderr)
		}
		fputs("Error: \(message)\n", stderr)
		hadError = true
	}
}
