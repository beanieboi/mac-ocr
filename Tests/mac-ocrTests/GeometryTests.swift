import CoreGraphics
import Testing

@testable import MacOcrCore

/// Coordinate-space conversions: mac-ocr emits top-left-origin normalized
/// boxes; Vision's `regionOfInterest` expects bottom-left origin. These pin
/// the TL→BL flip and the ROI default.
@Suite("Geometry")
struct GeometryTests {

	@Test func ocrOptionsROIDefaultsToNil() {
		#expect(OCROptions().regionOfInterest == nil)
	}

	// MARK: CGRect(BoundingBox) — TL→BL inverse for Vision API

	@Test func cgRectFromBoundingBoxInvertsToVisionBL() {
		// BoundingBox is TL-origin; CGRect(BoundingBox) converts back to Vision's BL-origin.
		let box = BoundingBox(x: 0.25, y: 0.50, width: 0.30, height: 0.20)
		let rect = CGRect(box)
		#expect(Double(rect.origin.x) == box.x)
		// BL y = 1 - TL_y - height
		#expect(Double(rect.origin.y) == 1.0 - box.y - box.height)
		#expect(Double(rect.size.width) == box.width)
		#expect(Double(rect.size.height) == box.height)
	}

	@Test func cgRectFromBoundingBoxMatchesVisionROI() {
		// Full-image TL box (0,0,1,1) maps to Vision's full-image CGRect (0,0,1,1).
		let box = BoundingBox(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
		let rect = CGRect(box)
		#expect(rect == CGRect(x: 0, y: 0, width: 1, height: 1))
	}

	@Test func cgRectFromBoundingBoxClampsBottomEdgeRounding() {
		let box = BoundingBox(x: 0.0, y: 0.8, width: 1.0, height: 0.2)
		let rect = CGRect(box)
		#expect(rect == CGRect(x: 0, y: 0, width: 1, height: 0.2))
	}
}
