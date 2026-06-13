import Foundation

extension FileHandle {
	/// Whether this handle is an interactive terminal. CLI-layer concern:
	/// drives stdin fallback, progress rendering, and the `-o -` TTY refusal.
	var isTerminal: Bool {
		isatty(fileDescriptor) != 0
	}
}
