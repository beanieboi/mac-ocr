import Darwin
import Foundation
import MacOcrCore
import Testing

@testable import MacOcrCLI

@Suite("MachineErrorReporter", .serialized)
struct MachineErrorReporterTests {
	/// Pins the full envelope shape, including the `requires` field — the
	/// `unavailable` kind is part of the fd-3 schema contract even though the
	/// OCR-only binary never emits it today.
	@Test func reportWritesFullEnvelopeToFd3() throws {
		let previousFormat = getenv("MAC_OCR_ERROR_FORMAT").map { String(cString: $0) }
		defer {
			if let previousFormat {
				setenv("MAC_OCR_ERROR_FORMAT", previousFormat, 1)
			} else {
				unsetenv("MAC_OCR_ERROR_FORMAT")
			}
		}
		setenv("MAC_OCR_ERROR_FORMAT", "json", 1)

		let previousFD3 = dup(3)
		var fds: [Int32] = [0, 0]
		guard pipe(&fds) == 0 else {
			throw NSError(domain: "MachineErrorReporterTests", code: Int(errno))
		}
		let readFD = dup(fds[0])
		close(fds[0])
		let writeFD = fds[1]
		guard readFD != -1 else {
			close(writeFD)
			throw NSError(domain: "MachineErrorReporterTests", code: Int(errno))
		}
		defer {
			close(readFD)
			if previousFD3 >= 0 {
				dup2(previousFD3, 3)
				close(previousFD3)
			} else {
				close(3)
			}
		}

		guard dup2(writeFD, 3) != -1 else {
			close(writeFD)
			throw NSError(domain: "MachineErrorReporterTests", code: Int(errno))
		}
		close(writeFD)

		MachineErrorReporter.report(
			kind: .unavailable,
			code: "vision_unavailable",
			message: "'lens-smudge' is not available on this OS (requires macOS 26+)",
			exitCode: 1,
			command: "lens-smudge",
			requires: "macOS 26+"
		)
		close(3)

		var data = Data()
		var buffer = [UInt8](repeating: 0, count: 4096)
		while true {
			let count = Darwin.read(readFD, &buffer, buffer.count)
			if count > 0 {
				data.append(buffer, count: count)
				continue
			}
			break
		}

		let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
		#expect(envelope["schema"] as? String == "mac-ocr.error")
		#expect(envelope["schemaVersion"] as? Int == 1)
		#expect(envelope["kind"] as? String == "unavailable")
		#expect(envelope["code"] as? String == "vision_unavailable")
		#expect(envelope["message"] as? String == "'lens-smudge' is not available on this OS (requires macOS 26+)")
		#expect(envelope["exitCode"] as? Int == 1)
		#expect(envelope["command"] as? String == "lens-smudge")
		#expect(envelope["requires"] as? String == "macOS 26+")
	}
}
