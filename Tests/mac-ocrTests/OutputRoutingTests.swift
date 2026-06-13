import Foundation
import Testing

/// End-to-end coverage of analysis output routing that had none:
/// the `[page]` per-page split (one file per page instead of consolidated),
/// file-mode JSON content shape, and the `==> name <==` multi-source text
/// headers on stdout.
@Suite(.serialized) struct OutputRoutingTests {

	private func makeTempDir() throws -> String {
		let tempDir = NSTemporaryDirectory() + "mac-ocr-routing-\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
		return tempDir
	}

	@Test func pageTemplateWritesOneTextFilePerPage() throws {
		let tempDir = try makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: tempDir) }

		let result = try TestSupport.run([
			TestSupport.fixturePath("multipage.pdf"), "-o", tempDir + "/[name]-[page].txt",
		])
		#expect(result.exitCode == 0, "stderr: \(result.stderr)")

		let expectations = [
			(file: "multipage-1.txt", text: "Page One"),
			(file: "multipage-2.txt", text: "Page Two"),
			(file: "multipage-3.txt", text: "Page Three"),
		]
		for expectation in expectations {
			let content = try String(contentsOfFile: tempDir + "/" + expectation.file, encoding: .utf8)
			#expect(content.contains(expectation.text), "\(expectation.file): \(content)")
		}
		let written = try FileManager.default.contentsOfDirectory(atPath: tempDir).sorted()
		#expect(written == ["multipage-1.txt", "multipage-2.txt", "multipage-3.txt"])
	}

	@Test func pageTemplateWritesSingleElementJsonArrayPerPage() throws {
		let tempDir = try makeTempDir()
		defer { try? FileManager.default.removeItem(atPath: tempDir) }

		let result = try TestSupport.run([
			TestSupport.fixturePath("multipage.pdf"), "--format", "json",
			"-o", tempDir + "/[name]-[page].json",
		])
		#expect(result.exitCode == 0, "stderr: \(result.stderr)")

		for page in 1...3 {
			let path = tempDir + "/multipage-\(page).json"
			let data = try Data(contentsOf: URL(fileURLWithPath: path))
			let array = try #require(
				try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
				"expected a JSON array in \(path)"
			)
			#expect(array.count == 1)
			#expect(array.first?["page"] as? Int == page)
			#expect(array.first?["pageCount"] as? Int == 3)
		}
	}

	@Test func ocrRefusesAPdfOutputExtension() throws {
		// `ocr -o x.pdf` would write recognized text into a file wearing a
		// .pdf name — the user almost certainly wants searchable-pdf.
		let result = try TestSupport.run([TestSupport.fixturePath("hello.png"), "-o", "notes.pdf"])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("searchable-pdf"), "must point at the right command; got: \(result.stderr)")

		let template = try TestSupport.run([TestSupport.fixturePath("hello.png"), "-o", "[name].PDF"])
		#expect(template.exitCode == 64, "the guard is case-insensitive and covers templates")
	}

	@Test func ocrRefusesDashOutput() throws {
		// stdout is already the default destination; `-o -` would create a
		// file literally named "-".
		let result = try TestSupport.run([TestSupport.fixturePath("hello.png"), "-o", "-"])
		#expect(result.exitCode == 64)
		#expect(result.stderr.contains("stdout"), "got: \(result.stderr)")
	}

	@Test func multipleSourcesShowHeadersInTextOutput() throws {
		let result = try TestSupport.run([
			TestSupport.fixturePath("hello.png"), TestSupport.fixturePath("empty.png"),
		])
		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdout.contains("==> \(TestSupport.fixturePath("hello.png")) <=="))
		#expect(result.stdout.contains("==> \(TestSupport.fixturePath("empty.png")) <=="))
	}
}
