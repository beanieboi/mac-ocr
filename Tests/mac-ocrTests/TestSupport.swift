import Foundation
import Testing

/// Shared helpers used by every command-level test suite. Spawns the built
/// `mac-ocr` binary as a subprocess and returns captured stdout/stderr/
/// exit code. Both `stdoutData` (raw bytes for artifact commands) and
/// `stdout` (UTF-8 decoded for analysis commands) are exposed.
enum TestSupport {
	static let packageRoot = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	static let fixturesURL =
		packageRoot
		.appendingPathComponent("Tests")
		.appendingPathComponent("fixtures")

	static let binaryURL =
		packageRoot
		.appendingPathComponent(".build")
		.appendingPathComponent("debug")
		.appendingPathComponent("mac-ocr")

	static func fixturePath(_ name: String) -> String {
		fixturesURL.appendingPathComponent(name).path
	}

	struct RunResult {
		let stdoutData: Data
		let stderrData: Data
		let exitCode: Int32

		var stdout: String { String(data: stdoutData, encoding: .utf8) ?? "" }
		var stderr: String { String(data: stderrData, encoding: .utf8) ?? "" }
	}

	static func run(
		_ arguments: [String] = [],
		stdinData: Data? = nil,
		environment: [String: String]? = nil
	) throws -> RunResult {
		VisionGate.shared.acquireBlocking()
		defer { VisionGate.shared.release() }

		let process = Process()
		process.executableURL = binaryURL
		process.arguments = arguments
		if let environment {
			process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
		}

		let stdoutPipe = Pipe()
		let stderrPipe = Pipe()
		process.standardOutput = stdoutPipe
		process.standardError = stderrPipe

		let stdinPipe = Pipe()
		process.standardInput = stdinPipe
		if let stdinData {
			stdinPipe.fileHandleForWriting.write(stdinData)
		}
		stdinPipe.fileHandleForWriting.closeFile()

		try process.run()

		var stdoutData = Data()
		var stderrData = Data()
		let group = DispatchGroup()

		group.enter()
		DispatchQueue.global().async {
			stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
			group.leave()
		}

		group.enter()
		DispatchQueue.global().async {
			stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
			group.leave()
		}

		process.waitUntilExit()
		group.wait()

		return RunResult(
			stdoutData: stdoutData,
			stderrData: stderrData,
			exitCode: process.terminationStatus
		)
	}

	/// Parse `string` as one complete JSON document. Strict by design: any
	/// non-JSON bytes on stdout (a stray print, a warning) must fail the
	/// test — clean stdout is part of the CLI's contract.
	static func parseJSON(_ string: String) throws -> Any {
		try JSONSerialization.jsonObject(with: Data(string.utf8))
	}

	// MARK: - Snapshot helpers

	static let snapshotsURL =
		packageRoot
		.appendingPathComponent("Tests")
		.appendingPathComponent("mac-ocrTests")
		.appendingPathComponent("Snapshots")

	static func normalizeSnapshotText(_ text: String) -> String {
		normalizeDecimalPrecision(normalizePackageRoot(normalizeRequestRevisions(normalizeUUIDs(text))))
	}

	/// `requestRevision` reports the Vision model revision, which bumps with
	/// macOS releases. Normalize it so snapshots pin the schema, not the model.
	private static func normalizeRequestRevisions(_ text: String) -> String {
		guard let regex = try? NSRegularExpression(pattern: #"("requestRevision"\s*:\s*)\d+"#) else { return text }
		return regex.stringByReplacingMatches(
			in: text,
			range: NSRange(text.startIndex..., in: text),
			withTemplate: "$1<revision>"
		)
	}

	private static func normalizeUUIDs(_ text: String) -> String {
		let pattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
		return regex.stringByReplacingMatches(
			in: text,
			range: NSRange(text.startIndex..., in: text),
			withTemplate: "00000000-0000-0000-0000-000000000000"
		)
	}

	private static func normalizePackageRoot(_ text: String) -> String {
		[
			packageRoot.path,
			packageRoot.path.replacingOccurrences(of: "/", with: "\\/"),
		].reduce(text) { output, root in
			output.replacingOccurrences(of: root, with: "<package-root>")
		}
	}

	private static func normalizeDecimalPrecision(_ text: String) -> String {
		guard let regex = try? NSRegularExpression(pattern: "-?\\d+\\.\\d+") else { return text }
		var output = text
		let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))

		for match in matches.reversed() {
			guard
				let range = Range(match.range, in: output),
				let value = Double(String(output[range]))
			else {
				continue
			}

			output.replaceSubrange(range, with: String(format: "%.1f", value))
		}

		return output
	}

	/// Compare `actual` (normalized) against the golden file at
	/// `Snapshots/<name>.txt`, failing the current test on mismatch. With
	/// `MAC_OCR_UPDATE_SNAPSHOTS=1` set, (re)write the golden instead of
	/// comparing.
	static func assertSnapshot(
		name: String,
		actual: String,
		sourceLocation: SourceLocation = #_sourceLocation
	) throws {
		let goldenURL = snapshotsURL.appendingPathComponent("\(name).txt")
		let normalizedActual = normalizeSnapshotText(actual)

		if ProcessInfo.processInfo.environment["MAC_OCR_UPDATE_SNAPSHOTS"] == "1" {
			try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
			try normalizedActual.write(to: goldenURL, atomically: true, encoding: .utf8)
			return
		}

		guard let expectedRaw = try? String(contentsOf: goldenURL, encoding: .utf8) else {
			throw SnapshotMissingError(name: name, goldenURL: goldenURL)
		}
		let expected = normalizeSnapshotText(expectedRaw)
		#expect(
			normalizedActual == expected,
			"Snapshot '\(name)' mismatch. Re-run with MAC_OCR_UPDATE_SNAPSHOTS=1 to accept the new output.",
			sourceLocation: sourceLocation
		)
	}

	/// Re-serialize a JSON document with sorted keys so snapshots don't depend
	/// on encoder key order (`MachineErrorReporter` uses a plain `JSONEncoder`,
	/// whose key order varies run to run).
	static func canonicalJSON(_ text: String) throws -> String {
		let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
		let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
		return String(decoding: data, as: UTF8.self)
	}

	// MARK: - fd-3 capture

	/// Run the binary via `/bin/sh` with fd 3 redirected to a capture file —
	/// `exec 3>file` opens fd 3 in the shell; `exec <binary>` then replaces the
	/// shell, so the binary inherits fd 3. Used by machine-error envelope tests
	/// (`MAC_OCR_ERROR_FORMAT=json` is set by default).
	static func runCapturingFd3(
		_ args: [String],
		environment extra: [String: String] = ["MAC_OCR_ERROR_FORMAT": "json"]
	) throws -> (exitCode: Int32, fd3: String) {
		let tempDir = NSTemporaryDirectory() + "mac-ocr-fd3-\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(atPath: tempDir) }
		let fd3Path = tempDir + "/fd3.json"

		func shellQuote(_ value: String) -> String {
			"'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
		}
		let binary = shellQuote(binaryURL.path)
		let joinedArgs = args.map(shellQuote).joined(separator: " ")
		let script = "exec 3>\(shellQuote(fd3Path)); exec \(binary) \(joinedArgs)"

		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-c", script]
		var environment = ProcessInfo.processInfo.environment
		for (key, value) in extra {
			environment[key] = value
		}
		process.environment = environment

		let outPipe = Pipe()
		let errPipe = Pipe()
		process.standardOutput = outPipe
		process.standardError = errPipe
		process.standardInput = FileHandle.nullDevice

		try process.run()
		_ = outPipe.fileHandleForReading.readDataToEndOfFile()
		_ = errPipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()

		let fd3 = (try? String(contentsOfFile: fd3Path, encoding: .utf8)) ?? ""
		return (process.terminationStatus, fd3)
	}
}

struct SnapshotMissingError: LocalizedError {
	let name: String
	let goldenURL: URL

	var errorDescription: String? {
		"Snapshot '\(name)' not found at \(goldenURL.path). Run with MAC_OCR_UPDATE_SNAPSHOTS=1 to create it."
	}
}
