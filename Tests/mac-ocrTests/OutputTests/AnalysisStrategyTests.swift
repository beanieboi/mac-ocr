import CoreGraphics
import Foundation
import Testing

@testable import MacOcrCore

// MARK: - Analysis strategy tests

@Suite("OutputStrategy.analysis")
struct AnalysisStrategyTests {

	@Test func textFormatPrintsTextOutput() async throws {
		// The strategy writes to stdout; we verify no error is thrown.
		let strategy = try OutputStrategy<AnalysisPayload>.analysis(
			format: .text,
			outputMode: .off,
			totalSources: 1
		)

		let context = makeContext(page: 1, pageCount: 1)
		try await strategy.onResult(AnalysisPayload(label: "hello"), context)
		try await strategy.onFinish()
	}

	@Test func jsonlFormatDoesNotThrow() async throws {
		let strategy = try OutputStrategy<AnalysisPayload>.analysis(
			format: .jsonl,
			outputMode: .off,
			totalSources: 1
		)
		let context = makeContext(page: 1, pageCount: 1)
		try await strategy.onResult(AnalysisPayload(label: "jsonl-result"), context)
		try await strategy.onFinish()
	}

	@Test func jsonFormatAccumulatesAndFlushesOnFinish() async throws {
		let strategy = try OutputStrategy<AnalysisPayload>.analysis(
			format: .json,
			outputMode: .off,
			totalSources: 1
		)
		let context = makeContext(page: 1, pageCount: 1)
		// First call: buffers
		try await strategy.onResult(AnalysisPayload(label: "first"), context)
		// Second call: buffers
		try await strategy.onResult(AnalysisPayload(label: "second"), context)
		// onFinish: flushes — should not throw
		try await strategy.onFinish()
	}

	// MARK: - Template mode (alongside each input)

	@Test func outputTemplateCapturesAndFlushesOnSourceDone() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let tempFile = tempDir.appendingPathComponent("strategy-test-\(UUID().uuidString).png")

		// Create a tiny dummy file so the loader can open it
		let fixture = EngineTestSupport.fixturesURL.appendingPathComponent("hello.png")
		try FileManager.default.copyItem(at: fixture, to: tempFile)
		defer { try? FileManager.default.removeItem(at: tempFile) }

		// `[dir]/[name].txt` writes next to the input (the `--sidecar` replacement).
		let strategy = try OutputStrategy<AnalysisPayload>.analysis(
			format: .text,
			outputMode: .template(try OutputTemplate(template: "[dir]/[name].txt")),
			totalSources: 1
		)

		let loader = try await openSource(.file(tempFile.path))
		let context = PageContext(
			source: .file(tempFile.path),
			page: 1,
			pageCount: 1,
			loader: loader,
			width: 10,
			height: 10
		)

		try await strategy.onResult(AnalysisPayload(label: "written"), context)
		try await strategy.onSourceDone(.file(tempFile.path), loader)

		let outputPath = tempFile.deletingPathExtension().path + ".txt"
		defer { try? FileManager.default.removeItem(atPath: outputPath) }
		let written = try String(contentsOfFile: outputPath, encoding: .utf8)
		#expect(written.contains("written"))
	}

	// MARK: - Directory mode

	@Test func outputDirectoryModeWritesToCustomDir() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let tempFile = tempDir.appendingPathComponent("strategy-dir-test-\(UUID().uuidString).png")
		let outputDir = tempDir.appendingPathComponent("strategy-out-\(UUID().uuidString)")

		let fixture = EngineTestSupport.fixturesURL.appendingPathComponent("hello.png")
		try FileManager.default.copyItem(at: fixture, to: tempFile)
		defer {
			try? FileManager.default.removeItem(at: tempFile)
			try? FileManager.default.removeItem(at: outputDir)
		}

		let strategy = try OutputStrategy<AnalysisPayload>.analysis(
			format: .text,
			outputMode: .directory(outputDir.path),
			totalSources: 1
		)

		let loader = try await openSource(.file(tempFile.path))
		let context = PageContext(
			source: .file(tempFile.path),
			page: 1,
			pageCount: 1,
			loader: loader,
			width: 10,
			height: 10
		)

		try await strategy.onResult(AnalysisPayload(label: "dir-written"), context)
		try await strategy.onSourceDone(.file(tempFile.path), loader)

		// Output should be in outputDir, not next to tempFile.
		let basename = tempFile.lastPathComponent
		let expectedPath = outputDir.appendingPathComponent(basename + ".txt").path
		#expect(FileManager.default.fileExists(atPath: expectedPath), "expected output at \(expectedPath)")
		let written = try String(contentsOfFile: expectedPath, encoding: .utf8)
		#expect(written.contains("dir-written"))
	}

	@Test func outputDirectoryModeCreatesNonexistentDir() async throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("strategy-mkdir-\(UUID().uuidString)")
		let tempFile = root.appendingPathComponent("hello.png")
		// Use a deeply nested directory that doesn't exist yet inside the same root
		let outputDir = root.appendingPathComponent("nested/new/dir")

		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let fixture = EngineTestSupport.fixturesURL.appendingPathComponent("hello.png")
		try FileManager.default.copyItem(at: fixture, to: tempFile)

		let strategy = try OutputStrategy<AnalysisPayload>.analysis(
			format: .text,
			outputMode: .directory(outputDir.path),
			totalSources: 1
		)

		let loader = try await openSource(.file(tempFile.path))
		let context = PageContext(
			source: .file(tempFile.path),
			page: 1,
			pageCount: 1,
			loader: loader,
			width: 10,
			height: 10
		)

		// Should not throw — directory is created automatically.
		try await strategy.onResult(AnalysisPayload(label: "mkdir"), context)
		try await strategy.onSourceDone(.file(tempFile.path), loader)

		#expect(FileManager.default.fileExists(atPath: outputDir.path))
	}

	// MARK: - Template mode

	@Test func outputTemplateModeRendersPlaceholders() async throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("strategy-tmpl-\(UUID().uuidString)")
		let inputFile = root.appendingPathComponent("hello.png")
		let outputDir = root.appendingPathComponent("out")

		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let fixture = EngineTestSupport.fixturesURL.appendingPathComponent("hello.png")
		try FileManager.default.copyItem(at: fixture, to: inputFile)

		let templateString = outputDir.path + "/[name]-processed.[ext].txt"
		let template = try OutputTemplate(template: templateString)

		let strategy = try OutputStrategy<AnalysisPayload>.analysis(
			format: .text,
			outputMode: .template(template),
			totalSources: 1
		)

		let loader = try await openSource(.file(inputFile.path))
		let context = PageContext(
			source: .file(inputFile.path),
			page: 1,
			pageCount: 1,
			loader: loader,
			width: 10,
			height: 10
		)

		try await strategy.onResult(AnalysisPayload(label: "template-result"), context)
		try await strategy.onSourceDone(.file(inputFile.path), loader)

		// Template: out/hello-processed.png.txt
		let expectedPath = outputDir.appendingPathComponent("hello-processed.png.txt").path
		#expect(FileManager.default.fileExists(atPath: expectedPath), "expected at \(expectedPath)")
		let written = try String(contentsOfFile: expectedPath, encoding: .utf8)
		#expect(written.contains("template-result"))
	}

	@Test func outputTemplateCollisionDoesNotOverwriteFirstAnalysisOutput() async throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("strategy-analysis-collision-\(UUID().uuidString)")
		let firstInput = root.appendingPathComponent("a/report.png")
		let secondInput = root.appendingPathComponent("b/report.png")
		let outputPath = root.appendingPathComponent("out/report.txt")

		try FileManager.default.createDirectory(at: firstInput.deletingLastPathComponent(), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: secondInput.deletingLastPathComponent(), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let template = try OutputTemplate(template: root.appendingPathComponent("out/[name].txt").path)
		let strategy = try OutputStrategy<AnalysisPayload>.analysis(
			format: .text,
			outputMode: .template(template),
			totalSources: 2
		)

		let firstContext = makeContext(sourcePath: firstInput.path)
		try await strategy.onResult(AnalysisPayload(label: "first-output"), firstContext)
		try await strategy.onSourceDone(.file(firstInput.path), firstContext.loader)

		let secondContext = makeContext(sourcePath: secondInput.path)
		try await strategy.onResult(AnalysisPayload(label: "second-output"), secondContext)
		await #expect(throws: (any Error).self) {
			try await strategy.onSourceDone(.file(secondInput.path), secondContext.loader)
		}

		let written = try String(contentsOfFile: outputPath.path, encoding: .utf8)
		#expect(written.contains("first-output"))
		#expect(!written.contains("second-output"))
	}
}
