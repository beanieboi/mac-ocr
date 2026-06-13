import Darwin
import Foundation
import Testing

/// Verifies `searchable-pdf` refuses to write a PDF to a terminal *before* it
/// spends time rendering and OCRing input. Drives the binary with a pseudo-tty
/// as stdout so `FileHandle.standardOutput.isTerminal` is true in the child.
@Suite(.serialized) struct SearchablePDFTerminalTests {

	@Test func refusesTerminalOutputBeforeRendering() throws {
		// `-o -` requests stdout; on a terminal that's refused. `invalid.txt`
		// would otherwise fail during render with "Cannot read image", so getting
		// exit 64 + a terminal error proves the guard runs first (in validate).
		let result = try runWithTerminalStdout([
			"searchable-pdf", "-o", "-", TestSupport.fixturePath("invalid.txt"),
		])
		#expect(result.exitCode == 64, "Expected usage exit 64; got \(result.exitCode); stderr: \(result.stderr)")
		#expect(
			result.stderr.lowercased().contains("terminal"),
			"Expected a terminal-refusal error before any render work; got: \(result.stderr)"
		)
	}

	// MARK: - Helper

	private func runWithTerminalStdout(
		_ args: [String]
	) throws -> (exitCode: Int32, stderr: String) {
		let pty = try PTYSupport.open()

		let process = Process()
		process.executableURL = TestSupport.binaryURL
		process.arguments = args
		process.standardOutput = FileHandle(fileDescriptor: pty.slave, closeOnDealloc: true)
		let errorPipe = Pipe()
		process.standardError = errorPipe
		process.standardInput = FileHandle.nullDevice

		// Drain the master end so a child that does write to the pty can't block.
		let masterHandle = FileHandle(fileDescriptor: pty.master, closeOnDealloc: true)
		DispatchQueue.global().async { _ = masterHandle.readDataToEndOfFile() }

		try process.run()
		let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()

		return (process.terminationStatus, String(data: errorData, encoding: .utf8) ?? "")
	}
}
