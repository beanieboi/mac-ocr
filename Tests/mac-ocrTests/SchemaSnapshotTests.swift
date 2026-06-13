import Foundation
import Testing

/// Golden-file pinning of the public output schema — the JSON/JSONL result
/// envelopes and the fd-3 machine-error envelope are semver contracts, and
/// these snapshots make any shape change loudly visible in a diff.
///
/// Goldens live in `Tests/mac-ocrTests/Snapshots/`; regenerate deliberately
/// with `MAC_OCR_UPDATE_SNAPSHOTS=1`. Volatile values (UUIDs, the Vision
/// `requestRevision`, absolute paths, decimal precision) are normalized by
/// `TestSupport.normalizeSnapshotText` so the snapshots pin schema, not model
/// output.
@Suite(.serialized) struct SchemaSnapshotTests {

	@Test func jsonSchemaForSingleImage() throws {
		let result = try TestSupport.run([TestSupport.fixturePath("hello.png"), "--format", "json"])
		#expect(result.exitCode == 0)
		try TestSupport.assertSnapshot(name: "ocr-json-hello", actual: result.stdout)
	}

	@Test func jsonSchemaForMultipagePdf() throws {
		let result = try TestSupport.run([TestSupport.fixturePath("multipage.pdf"), "--format", "json"])
		#expect(result.exitCode == 0)
		try TestSupport.assertSnapshot(name: "ocr-json-multipage", actual: result.stdout)
	}

	@Test func jsonlSchemaForSingleImage() throws {
		let result = try TestSupport.run([TestSupport.fixturePath("hello.png"), "--format", "jsonl"])
		#expect(result.exitCode == 0)
		try TestSupport.assertSnapshot(name: "ocr-jsonl-hello", actual: result.stdout)
	}

	@Test func usageErrorEnvelopeSchema() throws {
		let run = try TestSupport.runCapturingFd3(["ocr", "--confidence", "abc"])
		#expect(run.exitCode == 64)
		// Canonicalized: the envelope encoder does not sort keys, so its raw
		// byte order varies run to run.
		try TestSupport.assertSnapshot(name: "envelope-usage", actual: TestSupport.canonicalJSON(run.fd3))
	}

	@Test func runtimeErrorEnvelopeSchema() throws {
		let run = try TestSupport.runCapturingFd3(["ocr", TestSupport.fixturePath("invalid.txt")])
		#expect(run.exitCode == 1)
		try TestSupport.assertSnapshot(name: "envelope-runtime", actual: TestSupport.canonicalJSON(run.fd3))
	}
}
