import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MacOcrCore

/// Shared raster/file helpers for the input-matrix suites: draw a known text
/// raster and encode it into arbitrary container formats via ImageIO, so the
/// suites need no committed binary fixtures.
enum InputMatrixSupport {
	static func drawText(_ string: String, at point: CGPoint, size: CGFloat, in context: CGContext) {
		let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
		let attributes: [NSAttributedString.Key: Any] = [
			NSAttributedString.Key(kCTFontAttributeName as String): font
		]
		let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
		context.textPosition = point
		CTLineDraw(line, context)
	}

	/// 400×100 white raster with black 40pt "Hello World" — the same recipe
	/// as the committed `hello.png` fixture.
	static func makeHelloRaster() -> CGImage {
		let context = CGContext(
			data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		)!
		context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
		context.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
		context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
		drawText("Hello World", at: CGPoint(x: 30, y: 35), size: 40, in: context)
		return context.makeImage()!
	}

	/// Encode `image` to `path` in the given container format, with optional
	/// image properties (e.g. an EXIF orientation tag).
	static func write(
		_ image: CGImage,
		to path: String,
		type: UTType,
		properties: [CFString: Any]? = nil
	) throws {
		let destination = try #require(
			CGImageDestinationCreateWithURL(
				URL(fileURLWithPath: path) as CFURL, type.identifier as CFString, 1, nil))
		CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
		#expect(CGImageDestinationFinalize(destination), "failed to encode \(type.identifier)")
	}

	static func makeTempDir(_ label: String) throws -> String {
		let path = NSTemporaryDirectory() + "mac-ocr-matrix-\(label)-\(UUID().uuidString)"
		try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
		return path
	}
}

/// Every container format ImageIO can encode must round-trip through OCR —
/// the CLI's input surface is "whatever ImageIO decodes", so pin the common
/// ones. Generated in-test; no fixtures.
@Suite(.serialized) struct FormatMatrixTests {

	@Test(arguments: [
		(UTType.jpeg, "jpg"),
		(UTType.tiff, "tiff"),
		(UTType.heic, "heic"),
		(UTType.gif, "gif"),
		(UTType.bmp, "bmp"),
		(UTType.png, "png"),
	])
	func recognizesTextInEncodedFormat(type: UTType, ext: String) throws {
		let directory = try InputMatrixSupport.makeTempDir("format")
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let path = directory + "/hello.\(ext)"
		try InputMatrixSupport.write(InputMatrixSupport.makeHelloRaster(), to: path, type: type)

		let result = try TestSupport.run([path])
		#expect(result.exitCode == 0, "\(ext): stderr: \(result.stderr)")
		#expect(result.stdout.contains("Hello World"), "\(ext): got: \(result.stdout)")
	}

	@Test func tooSmallImageFailsGracefully() throws {
		// Vision refuses inputs ≤2px per side; that must surface as a clean
		// runtime error, not a crash or a silent empty success.
		let directory = try InputMatrixSupport.makeTempDir("tiny")
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let context = CGContext(
			data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		)!
		context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
		context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
		let path = directory + "/tiny.png"
		try InputMatrixSupport.write(context.makeImage()!, to: path, type: .png)

		let result = try TestSupport.run([path])
		#expect(result.exitCode != 0)
		#expect(!result.stderr.isEmpty, "the failure must be reported on stderr")
	}

	@Test func filenamesWithSpacesQuotesAndUnicodeWork() throws {
		let directory = try InputMatrixSupport.makeTempDir("names")
		defer { try? FileManager.default.removeItem(atPath: directory) }
		let names = ["with spaces and 'quote.png", "日本語ファイル名 🎌.png"]
		for name in names {
			let path = directory + "/" + name
			try InputMatrixSupport.write(InputMatrixSupport.makeHelloRaster(), to: path, type: .png)
			let result = try TestSupport.run([path])
			#expect(result.exitCode == 0, "\(name): stderr: \(result.stderr)")
			#expect(result.stdout.contains("Hello World"), "\(name): got: \(result.stdout)")
		}
	}
}
