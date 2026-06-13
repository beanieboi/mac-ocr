#!/usr/bin/env swift
// One-shot generator for document test fixtures. Run manually; commit outputs.
//
// Usage:
//   swift scripts/generate-document-fixtures.swift
//
// Produces (in Tests/fixtures/):
//   - document-photo.png — synthetic "photographed document" composed from the
//     existing hello.png fixture, tilted with CoreImage perspectiveTransform,
//     and pasted onto a gray background. The result has real OCR-able text
//     ("Hello World"), a strong document shape (VNDetectDocumentSegmentation
//     hits ~0.99 confidence on macOS 26), and produces a measurably rectified
//     output after document-crop — everything Phase 3 tests need.
//   - encrypted.pdf — single vector-text page reading "Hello World", encrypted
//     with user+owner password "secret". The Node e2e password specs use it
//     (Node can't generate encrypted PDFs at test time).
//
// Determinism: the stripe widths below the text are a fixed array, not
// random, so regenerating from the same inputs yields byte-identical PNGs on
// the same macOS version (CoreImage rendering drifts across OS updates).
// encrypted.pdf is content-deterministic only — PDF encryption embeds random
// salts (and CG writes a CreationDate), so its bytes differ per run. Tests
// assert on behavior, never fixture bytes.

import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import ImageIO
import UniformTypeIdentifiers

let fixturesDir = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("Tests/fixtures")

let context = CIContext()

func loadCGImage(at url: URL) -> CGImage? {
	guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
	return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func writePNG(_ image: CGImage, to url: URL) throws {
	guard let destination = CGImageDestinationCreateWithURL(
		url as CFURL,
		UTType.png.identifier as CFString,
		1,
		nil
	) else {
		throw NSError(domain: "DocumentFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
	}
	CGImageDestinationAddImage(destination, image, nil)
	guard CGImageDestinationFinalize(destination) else {
		throw NSError(domain: "DocumentFixtures", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not finalize PNG"])
	}
}

let helloURL = fixturesDir.appendingPathComponent("hello.png")
guard let hello = loadCGImage(at: helloURL) else {
	fatalError("Could not load \(helloURL.path) — regenerate after building out the base fixtures")
}

// Step 1: compose a white "document page" with hello.png near the top and
// deterministic stripes below to simulate body text.
let docWidth = 400
let docHeight = 560
let colorSpace = CGColorSpaceCreateDeviceRGB()
let docContext = CGContext(
	data: nil,
	width: docWidth,
	height: docHeight,
	bitsPerComponent: 8,
	bytesPerRow: 0,
	space: colorSpace,
	bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
docContext.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
docContext.fill(CGRect(x: 0, y: 0, width: docWidth, height: docHeight))

let helloX = (docWidth - hello.width) / 2
let helloY = docHeight - hello.height - 60
docContext.draw(hello, in: CGRect(x: helloX, y: helloY, width: hello.width, height: hello.height))

docContext.setFillColor(CGColor(gray: 0, alpha: 1))
let stripeWidths = [280, 310, 250, 320, 290, 240, 300, 260]
for index in 0..<stripeWidths.count {
	let y = helloY - 40 - (index * 24)
	docContext.fill(CGRect(x: 40, y: y, width: stripeWidths[index], height: 4))
}
let document = docContext.makeImage()!

// Step 2: apply perspective transform — moderate distortion, enough to give
// Vision's document segmentation a clear quad to detect, not so extreme that
// OCR fails on the rectified output.
let perspective = CIFilter.perspectiveTransform()
perspective.inputImage = CIImage(cgImage: document)
perspective.topLeft = CGPoint(x: 50, y: CGFloat(docHeight) - 20)
perspective.topRight = CGPoint(x: CGFloat(docWidth) - 30, y: CGFloat(docHeight) - 45)
perspective.bottomLeft = CGPoint(x: 75, y: 35)
perspective.bottomRight = CGPoint(x: CGFloat(docWidth) - 65, y: 15)
let tilted = perspective.outputImage!

// Step 3: composite onto a gray canvas so the document has clear contrast
// against the "desk" background.
let canvasWidth = 600
let canvasHeight = 800
let canvasContext = CGContext(
	data: nil,
	width: canvasWidth,
	height: canvasHeight,
	bitsPerComponent: 8,
	bytesPerRow: 0,
	space: colorSpace,
	bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
canvasContext.setFillColor(CGColor(red: 0.35, green: 0.38, blue: 0.42, alpha: 1))
canvasContext.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
let tiltedCG = context.createCGImage(tilted, from: tilted.extent)!
let offsetX = (canvasWidth - tiltedCG.width) / 2
let offsetY = (canvasHeight - tiltedCG.height) / 2
canvasContext.draw(tiltedCG, in: CGRect(x: offsetX, y: offsetY, width: tiltedCG.width, height: tiltedCG.height))

let photographedDoc = canvasContext.makeImage()!
try writePNG(photographedDoc, to: fixturesDir.appendingPathComponent("document-photo.png"))
print("document-photo.png: \(photographedDoc.width)x\(photographedDoc.height)")

// encrypted.pdf: one 400×100pt page of vector "Hello World" (rasterized by the
// CLI's PDF renderer before OCR, so vector text keeps the fixture tiny),
// encrypted via the PDF context's password options.
var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 100)
let pdfURL = fixturesDir.appendingPathComponent("encrypted.pdf")
let pdfOptions: [CFString: Any] = [
	kCGPDFContextUserPassword: "secret",
	kCGPDFContextOwnerPassword: "secret",
]
guard
	let consumer = CGDataConsumer(url: pdfURL as CFURL),
	let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, pdfOptions as CFDictionary)
else {
	fatalError("Could not create PDF context for \(pdfURL.path)")
}
pdfContext.beginPDFPage(nil)
pdfContext.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
pdfContext.fill(mediaBox)
let helloLine = CTLineCreateWithAttributedString(
	CFAttributedStringCreate(
		nil,
		"Hello World" as CFString,
		[
			kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 40, nil),
			kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
		] as CFDictionary
	)
)
pdfContext.textPosition = CGPoint(x: 30, y: 30)
CTLineDraw(helloLine, pdfContext)
pdfContext.endPDFPage()
pdfContext.closePDF()
print("encrypted.pdf: 400x100pt, password \"secret\"")

print("✓ Wrote fixtures to \(fixturesDir.path)")
