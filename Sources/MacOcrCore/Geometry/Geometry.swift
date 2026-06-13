// mac-ocr emits TL-origin (top-left) coordinates universally. Apple Vision's
// native normalized coordinate space is BL-origin (bottom-left); all
// Geometry.swift helpers flip Y to TL. See docs/CLI.md (Coordinates).
//
// Flip formula:
//   CGRect:   y_tl = 1 - (rect.origin.y + rect.size.height)

import CoreGraphics
import Foundation
import Vision

/// Normalized 0–1 rectangle in top-left-origin coordinate space.
public struct BoundingBox: Codable, Sendable {
	public let x: Double
	public let y: Double
	public let width: Double
	public let height: Double

	public init(x: Double, y: Double, width: Double, height: Double) {
		self.x = x
		self.y = y
		self.width = width
		self.height = height
	}

	/// Build from Vision's normalized `CGRect` bounding box.
	public init(_ rect: CGRect) {
		self.x = Double(rect.origin.x)
		self.y = Double(1 - rect.origin.y - rect.size.height)
		self.width = Double(rect.size.width)
		self.height = Double(rect.size.height)
	}

	/// Build from any Vision observation that carries a bounding box.
	/// `VNDetectedObjectObservation` is the common base for face, text, barcode,
	/// rectangle, human, and animal observations.
	public init(_ observation: VNDetectedObjectObservation) {
		self.init(observation.boundingBox)
	}
}

extension CGRect {
	/// Build a normalized rect from a `BoundingBox`. Used when applying ROI to
	/// a `VNImageBasedRequest.regionOfInterest` (which expects Vision's
	/// bottom-left-origin `CGRect`).
	public init(_ boundingBox: BoundingBox) {
		let visionY = min(max(1 - boundingBox.y - boundingBox.height, 0), 1)
		self.init(
			x: boundingBox.x,
			y: visionY,
			width: boundingBox.width,
			height: boundingBox.height
		)
	}
}
