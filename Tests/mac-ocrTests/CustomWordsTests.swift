import Foundation
import Testing

/// Coverage for the custom-vocabulary flags (`-w` / `--custom-words` and
/// `--custom-words-file`) — previously entirely untested despite the committed
/// `words.txt` fixture. Recognition *bias* is Vision's business; these pin the
/// option plumbing and the file-validation error paths.
@Suite(.serialized) struct CustomWordsTests {

	@Test func customWordsFlagIsAccepted() throws {
		let result = try TestSupport.run([
			TestSupport.fixturePath("hello.png"), "-w", "Hello", "--custom-words", "World",
		])
		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdout.contains("Hello World"))
	}

	@Test func customWordsFileIsReadAndAccepted() throws {
		let result = try TestSupport.run([
			TestSupport.fixturePath("hello.png"), "--custom-words-file", TestSupport.fixturePath("words.txt"),
		])
		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdout.contains("Hello World"))
	}

	@Test func missingCustomWordsFileFailsValidation() throws {
		let result = try TestSupport.run([
			TestSupport.fixturePath("hello.png"), "--custom-words-file", "/nonexistent/words.txt",
		])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("Cannot read"), "stderr: \(result.stderr)")
	}

	@Test func directoryAsCustomWordsFileFailsValidation() throws {
		let result = try TestSupport.run([
			TestSupport.fixturePath("hello.png"), "--custom-words-file", TestSupport.fixturesURL.path,
		])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("Cannot read"), "stderr: \(result.stderr)")
	}

	@Test func searchablePdfValidatesCustomWordsFileToo() throws {
		let tempDir = NSTemporaryDirectory() + "mac-ocr-words-\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(atPath: tempDir) }

		let result = try TestSupport.run([
			"searchable-pdf", TestSupport.fixturePath("hello.png"),
			"--custom-words-file", "/nonexistent/words.txt",
			"-o", tempDir + "/out.pdf",
		])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("Cannot read"), "stderr: \(result.stderr)")
	}
}
