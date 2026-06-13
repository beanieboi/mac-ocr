import AppKit
import Foundation
import PDFKit
import Testing

/// Password-protected PDFs: rejected with a clear message when locked, unlocked
/// when the correct password is supplied via `--password` or the
/// `MAC_OCR_PDF_PASSWORD` env var.
@Suite(.serialized) struct EncryptedPDFTests {

	@Test func ocrReportsPasswordProtectedPdf() throws {
		let path = try makeEncryptedPDF()
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try TestSupport.run([path])

		#expect(result.exitCode != 0)
		#expect(result.stderr.lowercased().contains("password protected"), "stderr: \(result.stderr)")
	}

	@Test func searchablePdfReportsPasswordProtectedPdf() throws {
		let path = try makeEncryptedPDF()
		defer { try? FileManager.default.removeItem(atPath: path) }
		let output = path + ".ocr.pdf"
		defer { try? FileManager.default.removeItem(atPath: output) }

		let result = try TestSupport.run(["searchable-pdf", path, "-o", output])

		#expect(result.exitCode != 0)
		#expect(result.stderr.lowercased().contains("password protected"), "stderr: \(result.stderr)")
		#expect(!FileManager.default.fileExists(atPath: output), "must not write output for a locked PDF")
	}

	@Test func ocrUnlocksWithCorrectPassword() throws {
		let path = try makeEncryptedPDF(password: "secret")
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try TestSupport.run([path, "--password", "secret"])

		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdout.contains("Hello"), "stdout: \(result.stdout)")
	}

	@Test func ocrRejectsWrongPassword() throws {
		let path = try makeEncryptedPDF(password: "secret")
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try TestSupport.run([path, "--password", "wrong"])

		#expect(result.exitCode != 0)
		#expect(result.stderr.lowercased().contains("incorrect password"), "stderr: \(result.stderr)")
	}

	@Test func ocrUnlocksViaEnvironmentVariable() throws {
		let path = try makeEncryptedPDF(password: "secret")
		defer { try? FileManager.default.removeItem(atPath: path) }

		let result = try TestSupport.run([path], environment: ["MAC_OCR_PDF_PASSWORD": "secret"])

		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdout.contains("Hello"), "stdout: \(result.stdout)")
	}

	@Test func ocrUnlocksStdinInput() throws {
		// Stdin bytes take a different CGPDFDocument init than file paths
		// (data provider vs URL — PDFLoader.swift), and stdin is the only
		// input shape the Node API uses. Pin that decryption works there too.
		let path = try makeEncryptedPDF(password: "secret")
		defer { try? FileManager.default.removeItem(atPath: path) }
		let data = try Data(contentsOf: URL(fileURLWithPath: path))

		let result = try TestSupport.run(
			["-"],
			stdinData: data,
			environment: ["MAC_OCR_PDF_PASSWORD": "secret"]
		)

		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdout.contains("Hello"), "stdout: \(result.stdout)")
	}

	@Test func searchablePdfUnlocksWithCorrectPassword() throws {
		let path = try makeEncryptedPDF(password: "secret")
		defer { try? FileManager.default.removeItem(atPath: path) }
		let output = path + ".ocr.pdf"
		defer { try? FileManager.default.removeItem(atPath: output) }

		let result = try TestSupport.run(["searchable-pdf", path, "--password", "secret", "-o", output])

		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		let document = try #require(PDFDocument(url: URL(fileURLWithPath: output)))
		#expect((document.string ?? "").contains("Hello"))
	}

	/// Build a single-page PDF (containing the word "Hello") encrypted with the
	/// given user/owner password, written to a temp file. CGPDFDocument opens it
	/// but reports `isUnlocked == false` until unlocked.
	private func makeEncryptedPDF(password: String = "secret") throws -> String {
		let image = NSImage(size: NSSize(width: 240, height: 80))
		image.lockFocus()
		NSColor.white.set()
		NSRect(x: 0, y: 0, width: 240, height: 80).fill()
		("Hello" as NSString).draw(at: NSPoint(x: 12, y: 28), withAttributes: [.font: NSFont.systemFont(ofSize: 32)])
		image.unlockFocus()

		let document = PDFDocument()
		let page = try #require(PDFPage(image: image))
		document.insert(page, at: 0)

		let path = NSTemporaryDirectory() + "mac-ocr-enc-\(UUID().uuidString).pdf"
		let options: [PDFDocumentWriteOption: Any] = [
			.userPasswordOption: password,
			.ownerPasswordOption: password,
		]
		try #require(document.write(to: URL(fileURLWithPath: path), withOptions: options))
		return path
	}
}
