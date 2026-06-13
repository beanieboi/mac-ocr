import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MacOcrCore

/// All eight EXIF orientation tags must produce display-space results: the
/// recognized text and its bounding box must match the upright original no
/// matter how the pixels are stored. Each fixture is generated in-test by
/// applying the *inverse* of the tag's display transform to upright pixels,
/// so a tag-honoring reader sees the identical upright image.
///
/// Validated against ImageIO ground truth during the stress audit: mac-ocr's
/// geometry for every tag matches `kCGImageSourceCreateThumbnailWithTransform`.
@Suite(.serialized) struct ExifOrientationMatrixTests {

	@Test func allEightOrientationsMatchTheUprightGeometry() throws {
		let directory = try InputMatrixSupport.makeTempDir("exif")
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let upright = InputMatrixSupport.makeHelloRaster()

		func boundingBox(of path: String) throws -> (x: Double, y: Double, width: Double, height: Double) {
			let result = try TestSupport.run([path, "--format", "jsonl"])
			#expect(result.exitCode == 0, "\(path): stderr: \(result.stderr)")
			let object = try #require(
				try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
			#expect((object["text"] as? String)?.contains("Hello World") == true, "\(path): \(result.stdout)")
			#expect(object["width"] as? Int == 400, "display width must honor the tag")
			#expect(object["height"] as? Int == 100)
			let observations = try #require(object["observations"] as? [[String: Any]])
			let box = try #require(observations.first?["boundingBox"] as? [String: Double])
			return (box["x"]!, box["y"]!, box["width"]!, box["height"]!)
		}

		// Reference: orientation 1 (identity).
		let referencePath = directory + "/orientation-1.jpg"
		try InputMatrixSupport.write(
			storedImage(for: 1, upright: upright), to: referencePath, type: .jpeg,
			properties: [kCGImagePropertyOrientation: 1])
		let reference = try boundingBox(of: referencePath)

		for orientation in 2...8 {
			let path = directory + "/orientation-\(orientation).jpg"
			try InputMatrixSupport.write(
				storedImage(for: orientation, upright: upright), to: path, type: .jpeg,
				properties: [kCGImagePropertyOrientation: orientation])
			let box = try boundingBox(of: path)
			let tolerance = 0.05
			#expect(abs(box.x - reference.x) < tolerance, "orientation \(orientation): x \(box.x) vs \(reference.x)")
			#expect(abs(box.y - reference.y) < tolerance, "orientation \(orientation): y \(box.y) vs \(reference.y)")
			#expect(abs(box.width - reference.width) < tolerance, "orientation \(orientation): width")
			#expect(abs(box.height - reference.height) < tolerance, "orientation \(orientation): height")
		}
	}

	/// Stored pixels for an EXIF tag: the inverse of the tag's display
	/// transform applied to the upright image (CG coordinates, bottom-left
	/// origin). Tags 5-8 swap the stored canvas dimensions.
	private func storedImage(for orientation: Int, upright: CGImage) -> CGImage {
		let w = CGFloat(upright.width)
		let h = CGFloat(upright.height)
		let swaps = orientation >= 5
		let context = CGContext(
			data: nil, width: swaps ? Int(h) : Int(w), height: swaps ? Int(w) : Int(h),
			bitsPerComponent: 8, bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		)!
		switch orientation {
		case 2: context.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))  // flip H
		case 3: context.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))  // 180°
		case 4: context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h))  // flip V
		// Note: in CG's bottom-left space the *raster* transpose (tag 5) is
		// (x,y) → (h−y, w−x), and the transverse (tag 7) is the plain swap —
		// the reverse of what top-left-origin intuition suggests.
		case 5: context.concatenate(CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w))  // transpose
		case 6: context.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))  // 90° CCW stored
		case 7: context.concatenate(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))  // transverse
		case 8: context.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))  // 90° CW stored
		default: break
		}
		context.draw(upright, in: CGRect(x: 0, y: 0, width: w, height: h))
		return context.makeImage()!
	}
}
