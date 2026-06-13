import Foundation
import Testing

/// `-l/--language` validation: unsupported codes previously passed straight to
/// Vision, which yields silently empty results — the worst failure mode. They
/// must be rejected up front (exit 64) with a pointer to `mac-ocr languages`,
/// and near-miss casing must be canonicalized rather than rejected.
@Suite(.serialized) struct LanguageValidationTests {

	@Test func bogusLanguageFailsValidation() throws {
		let result = try TestSupport.run([TestSupport.fixturePath("hello.png"), "-l", "klingon"])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("Unsupported recognition language"), "stderr: \(result.stderr)")
		#expect(result.stderr.contains("mac-ocr languages"), "must point at the list command; stderr: \(result.stderr)")
	}

	@Test func multipleBogusLanguagesAreAllNamed() throws {
		let result = try TestSupport.run([
			TestSupport.fixturePath("hello.png"), "-l", "xx-XX", "-l", "yy-YY",
		])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("xx-XX") && result.stderr.contains("yy-YY"), "stderr: \(result.stderr)")
	}

	@Test func wrongCasingIsCanonicalizedNotRejected() throws {
		let result = try TestSupport.run([TestSupport.fixturePath("hello.png"), "-l", "en-us"])
		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdout.contains("Hello World"))
	}

	@Test func fastModeValidatesAgainstTheFastList() throws {
		// The hint must name the matching list command for the chosen level.
		let result = try TestSupport.run([
			TestSupport.fixturePath("hello.png"), "--fast", "-l", "klingon",
		])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("languages --fast"), "stderr: \(result.stderr)")
	}

	@Test func searchablePdfValidatesLanguagesToo() throws {
		let tempDir = NSTemporaryDirectory() + "mac-ocr-lang-\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(atPath: tempDir) }

		let result = try TestSupport.run([
			"searchable-pdf", TestSupport.fixturePath("hello.png"), "-l", "klingon",
			"-o", tempDir + "/out.pdf",
		])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("Unsupported recognition language"), "stderr: \(result.stderr)")
	}
}
