import Darwin
import Foundation
import Testing

/// Live progress for the `ocr` command. The counter renders on interactive
/// stderr — except when the results themselves are streaming to the same
/// terminal (text/jsonl to a stdout TTY), where the scrolling output *is*
/// the progress and a rewriting counter would fight it. Piped runs are
/// silent on success.
@Suite(.serialized) struct OCRProgressTests {

	@Test func fileOutputShowsALivePageCounter() throws {
		let directory = makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: directory) }

		let captured = try runWithPTY(
			["ocr", TestSupport.fixturePath("multipage.pdf"), "-o", directory + "/out.txt"],
			stderrOnPTY: true,
			stdoutOnPTY: false
		)

		#expect(captured.contains("[3/3]"), "expected a page counter for file output; got: \(captured)")
		#expect(captured.contains("multipage.pdf"), "counter labels the source; got: \(captured)")
	}

	@Test func redirectedStdoutShowsTheCounterToo() throws {
		// Text mode, but stdout is a pipe — nothing is scrolling on the
		// terminal, so interactive stderr gets the counter.
		let captured = try runWithPTY(
			["ocr", TestSupport.fixturePath("multipage.pdf")],
			stderrOnPTY: true,
			stdoutOnPTY: false
		)

		#expect(captured.contains("[3/3]"), "got: \(captured)")
	}

	@Test func textStreamingToTheTerminalShowsNoCounter() throws {
		// Both streams on the same terminal: the scrolling text is the
		// progress; a rewriting counter must not fight it.
		let captured = try runWithPTY(
			["ocr", TestSupport.fixturePath("multipage.pdf")],
			stderrOnPTY: true,
			stdoutOnPTY: true
		)

		#expect(captured.contains("Page One"), "results stream to the terminal; got: \(captured)")
		#expect(
			captured.range(of: #"\[\d+/\d+\]"#, options: .regularExpression) == nil,
			"no counter may fight the streaming text; got: \(captured)"
		)
	}

	@Test func multipleSourcesGetABatchPrefix() throws {
		let directory = makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: directory) }

		let captured = try runWithPTY(
			[
				"ocr", TestSupport.fixturePath("hello.png"), TestSupport.fixturePath("empty.png"),
				"-o", directory + "/",
			],
			stderrOnPTY: true,
			stdoutOnPTY: false
		)

		#expect(captured.contains("[1/2]"), "expected a batch prefix; got: \(captured)")
		#expect(captured.contains("[2/2]"), "expected a batch prefix; got: \(captured)")
	}

	@Test func pipedRunsAreSilentOnSuccess() throws {
		let directory = makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: directory) }

		let result = try TestSupport.run([
			"ocr", TestSupport.fixturePath("multipage.pdf"), "-o", directory + "/out.txt",
		])

		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stderr.isEmpty, "piped success must write nothing to stderr; got: \(result.stderr)")
	}

	// MARK: - Helpers

	private func makeTempDir() -> String {
		let path = NSTemporaryDirectory() + "mac-ocr-ocr-prog-\(UUID().uuidString)"
		try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
		return path
	}

	/// Run the binary with stderr (and optionally stdout) attached to one
	/// pseudo-terminal, returning everything written to it. Non-PTY stdout is
	/// drained to a pipe so streamed output never blocks.
	private func runWithPTY(
		_ args: [String],
		stderrOnPTY: Bool,
		stdoutOnPTY: Bool
	) throws -> String {
		VisionGate.shared.acquireBlocking()
		defer { VisionGate.shared.release() }

		let pty = try PTYSupport.open()
		let slaveHandle = FileHandle(fileDescriptor: pty.slave, closeOnDealloc: false)

		let process = Process()
		process.executableURL = TestSupport.binaryURL
		process.arguments = args
		process.standardInput = FileHandle.nullDevice
		process.standardError = stderrOnPTY ? slaveHandle : FileHandle.nullDevice
		let stdoutPipe = Pipe()
		if stdoutOnPTY {
			process.standardOutput = slaveHandle
		} else {
			process.standardOutput = stdoutPipe
		}

		let masterHandle = FileHandle(fileDescriptor: pty.master, closeOnDealloc: true)
		try process.run()
		// The child holds its own dup of the slave; close the parent's copy so
		// the master read sees EOF once the child exits.
		close(pty.slave)
		if !stdoutOnPTY {
			// Drain stdout concurrently so a full pipe never blocks the child.
			stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
				if handle.availableData.isEmpty {
					handle.readabilityHandler = nil
				}
			}
		}
		let data = masterHandle.readDataToEndOfFile()
		process.waitUntilExit()
		return String(data: data, encoding: .utf8) ?? ""
	}
}
