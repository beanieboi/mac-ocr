import Darwin
import Foundation
import Testing

/// Progress and output-path reporting for `searchable-pdf`. Status is
/// interactive-only (cp/tar convention): on a terminal, a live counter plus a
/// final `name → path` line; piped/redirected runs are completely silent on
/// success — stderr carries only real errors. There is no `--quiet` flag;
/// piped runs are already quiet.
@Suite(.serialized) struct SearchablePDFProgressTests {

	// MARK: - Non-interactive (TestSupport pipes stderr, so isTerminal == false)

	@Test func pipedSuccessIsCompletelySilent() throws {
		let directory = makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let input = try stage("hello.png", in: directory)

		let result = try TestSupport.run(["searchable-pdf", input])

		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stderr.isEmpty, "piped success must write nothing to stderr; got: \(result.stderr)")
		#expect(result.stdoutData.isEmpty)
		#expect(FileManager.default.fileExists(atPath: directory + "/hello.ocr.pdf"))
	}

	@Test func pipedMultipageRunIsSilentToo() throws {
		let directory = makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let input = try stage("multipage.pdf", in: directory)

		let result = try TestSupport.run(["searchable-pdf", input])

		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stderr.isEmpty, "got: \(result.stderr)")
		#expect(FileManager.default.fileExists(atPath: directory + "/multipage.ocr.pdf"))
	}

	@Test func pipedFailuresStillReportErrors() throws {
		// Interactive-only applies to *status*; errors must always reach
		// stderr, piped or not.
		let directory = makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: directory) }

		let result = try TestSupport.run([
			"searchable-pdf", TestSupport.fixturePath("invalid.txt"), "-o", directory + "/out.pdf",
		])

		#expect(result.exitCode != 0)
		#expect(result.stderr.contains("Error:"), "got: \(result.stderr)")
	}

	@Test func stdoutModeEmitsCleanBytesAndNoStatus() throws {
		let result = try TestSupport.run(
			["searchable-pdf", TestSupport.fixturePath("hello.png"), "-o", "-"]
		)

		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdoutData.prefix(5) == Data("%PDF-".utf8))
		#expect(result.stderr.isEmpty, "got: \(result.stderr)")
	}

	// MARK: - Interactive (stderr is a pseudo-terminal)

	@Test func showsLivePageCounterWhenStderrIsTerminal() throws {
		let directory = makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let input = try stage("multipage.pdf", in: directory)

		let stderr = try runWithTerminalStderr(["searchable-pdf", input])

		#expect(stderr.contains("[3/3]"), "expected a live page counter; got: \(stderr)")
		#expect(stderr.contains("\u{1b}["), "expected an ANSI clear sequence; got: \(stderr)")
		#expect(stderr.contains("multipage.ocr.pdf"), "expected the final path line; got: \(stderr)")
	}

	@Test func multipleInputsShowABatchPrefix() throws {
		let directory = makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let first = try stage("hello.png", in: directory)
		let second = directory + "/second.png"
		try FileManager.default.copyItem(atPath: first, toPath: second)

		let stderr = try runWithTerminalStderr(["searchable-pdf", first, second])

		#expect(stderr.contains("[1/2]"), "expected a batch prefix for input 1; got: \(stderr)")
		#expect(stderr.contains("[2/2]"), "expected a batch prefix for input 2; got: \(stderr)")
	}

	// MARK: - Helpers

	private func makeTempDir() -> String {
		let path = NSTemporaryDirectory() + "mac-ocr-spdf-prog-\(UUID().uuidString)"
		try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
		return path
	}

	private func stage(_ fixture: String, in directory: String) throws -> String {
		let destination = directory + "/" + fixture
		try FileManager.default.copyItem(atPath: TestSupport.fixturePath(fixture), toPath: destination)
		return destination
	}

	/// Run the binary with its stderr attached to a pseudo-terminal so the
	/// in-binary `isatty` check sees an interactive terminal. Returns everything
	/// written to that terminal.
	private func runWithTerminalStderr(_ args: [String]) throws -> String {
		VisionGate.shared.acquireBlocking()
		defer { VisionGate.shared.release() }

		let pty = try PTYSupport.open()

		let process = Process()
		process.executableURL = TestSupport.binaryURL
		process.arguments = args
		process.standardError = FileHandle(fileDescriptor: pty.slave, closeOnDealloc: false)
		process.standardOutput = FileHandle.nullDevice
		process.standardInput = FileHandle.nullDevice

		let masterHandle = FileHandle(fileDescriptor: pty.master, closeOnDealloc: true)
		try process.run()
		// The child holds its own dup of the slave; close the parent's copy so
		// the master read sees EOF once the child exits.
		close(pty.slave)
		let data = masterHandle.readDataToEndOfFile()
		process.waitUntilExit()
		return String(data: data, encoding: .utf8) ?? ""
	}
}
