import Foundation
import Testing

// MARK: - macOS availability guards

private let macOS11Available = ProcessInfo.processInfo.isOperatingSystemAtLeast(
	OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0)
)
private let macOS26Available = ProcessInfo.processInfo.isOperatingSystemAtLeast(
	OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
)

// MARK: - Helpers

private func run(_ arguments: [String]) throws -> TestSupport.RunResult {
	try TestSupport.run(arguments)
}

// MARK: - ROI integration tests

/// Tests that `--roi` is parsed, plumbed, and correctly flips coordinates for
/// each engine that had bugs or was previously missing the option.
@Suite(.serialized) struct ROITests {

	// MARK: - --roi validation (engine-agnostic)

	@Test func malformedROIIsRejected() throws {
		let result = try run(["ocr", "--roi", "bad", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode != 0)
		#expect(result.stderr.lowercased().contains("roi") || result.stderr.contains("x,y,w,h"))
	}

	@Test func roiWithTooFewComponentsIsRejected() throws {
		let result = try run(["ocr", "--roi", "0,0,1", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode != 0)
	}

	@Test func roiWithMalformedNumericTokenIsRejected() throws {
		let result = try run(["ocr", "--roi", "0,0,bad,1,1", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode == 64)
		#expect(result.stderr.lowercased().contains("roi"))
	}

	@Test func roiWithOutOfRangeValueIsRejected() throws {
		let result = try run(["ocr", "--roi", "0,0,2,1", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode != 0)
	}

	// MARK: - OCR --roi

	@Test func ocrFullROIPreservesText() throws {
		let result = try run(["ocr", "--roi", "0,0,1,1", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode == 0)
		#expect(result.stdout.contains("Hello World"))
	}

	@Test func ocrNarrowROIExcludesText() throws {
		// A 5%-height strip at the very top (y=0, h=0.05) should not contain text.
		let result = try run(["ocr", "--roi", "0,0,1,0.05", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode == 0)
		#expect(!result.stdout.contains("Hello World"))
	}

	// MARK: - Out-of-bounds ROI validation regression
	//
	// x+w and y+h must stay inside the normalized [0,1] image boundary, not
	// only have individually valid x/y/width/height components.

	@Test func roiWhereXPlusWidthExceedsOneShouldBeRejected() throws {
		// x=0.8, y=0.0, w=0.5, h=0.5 → x+w = 1.3 > 1.0 (out of bounds)
		let result = try run(["ocr", "--roi", "0.8,0.0,0.5,0.5", TestSupport.fixturePath("hello.png")])
		// Must reject at validation time (exit 64 = EX_USAGE), not at Vision runtime.
		#expect(result.exitCode == 64, "ROI x+w>1 should be rejected at validate(), not propagated to Vision runtime")
		#expect(
			result.stderr.lowercased().contains("roi") && result.stderr.lowercased().contains("bound"),
			"error should explain the out-of-bounds problem"
		)
	}

	@Test func roiWhereYPlusHeightExceedsOneShouldBeRejected() throws {
		let result = try run(["ocr", "--roi", "0.0,0.8,0.5,0.5", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode == 64, "ROI y+h>1 should be rejected at validate(), not propagated to Vision runtime")
		#expect(
			result.stderr.lowercased().contains("roi") && result.stderr.lowercased().contains("bound"),
			"error should explain the out-of-bounds problem"
		)
	}

	@Test func roiAuditExampleShouldBeRejected() throws {
		// The exact example from the audit: 0.8,0.8,0.5,0.5 → both dimensions exceed
		let result = try run(["ocr", "--roi", "0.8,0.8,0.5,0.5", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode == 64, "ROI 0.8,0.8,0.5,0.5 should be rejected at validate()")
		#expect(
			result.stderr.lowercased().contains("roi") && result.stderr.lowercased().contains("bound"),
			"error should explain the out-of-bounds problem"
		)
	}

	@Test func roiAtExactBoundaryIsAccepted() throws {
		// Boundary case: x+w = 1.0, y+h = 1.0 — exactly fills image, must be ACCEPTED
		let result = try run(["ocr", "--roi", "0.0,0.0,1.0,1.0", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode == 0, "ROI exactly filling the image (sum = 1.0) is valid and must be accepted")
	}

	@Test func roiAtBottomEdgeBoundaryIsAccepted() throws {
		let result = try run(["ocr", "--roi", "0.0,0.8,1.0,0.2", TestSupport.fixturePath("hello.png")])
		#expect(result.exitCode == 0, "ROI ending at the bottom edge is valid and must be accepted")
	}
}
