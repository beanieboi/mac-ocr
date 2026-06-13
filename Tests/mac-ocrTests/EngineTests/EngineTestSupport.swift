import CoreGraphics
import Foundation
import ImageIO

@testable import MacOcrCore

/// Support helpers for engine-level unit tests that call engine functions
/// directly via `@testable import MacOcrCore`. No subprocess, no binary
/// build, no JSONL parsing — just `(CGImage, Orientation, Options) -> Output`
/// round trips.
enum EngineTestSupport {
	static let fixturesURL = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appendingPathComponent("fixtures")

	/// Load a fixture PNG/JPEG into an upright `CGImage`. Returns the image
	/// plus the detected EXIF orientation (most fixtures are `.up`, but the
	/// rotated test image isn't).
	static func loadImage(_ name: String) throws -> (image: CGImage, orientation: CGImagePropertyOrientation) {
		let url = fixturesURL.appendingPathComponent(name)
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
		else {
			throw MessageError("Could not load fixture \(name)")
		}
		let orientation: CGImagePropertyOrientation
		if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
			let raw = properties[kCGImagePropertyOrientation] as? UInt32,
			let parsed = CGImagePropertyOrientation(rawValue: raw)
		{
			orientation = parsed
		} else {
			orientation = .up
		}
		return (image, orientation)
	}
}
