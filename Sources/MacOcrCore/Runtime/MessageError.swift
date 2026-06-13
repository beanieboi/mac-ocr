import Foundation

public struct MessageError: LocalizedError {
	public let message: String
	public var errorDescription: String? { message }

	public init(_ message: String) {
		self.message = message
	}
}

/// A user-correctable CLI usage failure raised from core helpers.
///
/// `MacOcrCore` deliberately does not depend on Swift ArgumentParser. The
/// CLI target maps this error to ArgumentParser's `ValidationError` so command
/// users still get usage exit code 64 and command-specific help.
public struct UsageError: LocalizedError {
	public let message: String
	public var errorDescription: String? { message }

	public init(_ message: String) {
		self.message = message
	}
}

/// Silent process-exit signal for batch runs that already reported each
/// per-source error to stderr.
public struct BatchRunFailure: Error {
	public let code: Int32

	public init(code: Int32 = 1) {
		self.code = code
	}
}
