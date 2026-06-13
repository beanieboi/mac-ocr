import CoreGraphics
import Foundation
import ImageIO

// Auto mode bounds: never render below 144 (the previous default — works fine
// for vector PDFs) and never above 600 (memory cap; Vision rarely benefits
// from higher input). Explicit --pdf-dpi values bypass the auto cap and are
// validated against the same 72–600 range at the CLI layer.
private let autoDpiFloor = 144
let autoDpiCeiling = 600

// Hard cap on the rendered bitmap size. A legitimate A0 page at 300 DPI is
// ~140 MP, so 200 MP leaves headroom for slightly oversized stock without
// opening the door to adversarial PDFs that request multi-gigabyte bitmaps.
private let maxRenderPixels: Int64 = 200_000_000

func openPDFFromFile(path: String, url: URL, dpi: Int?, password: String?) throws -> ImageLoader {
	guard let document = CGPDFDocument(url as CFURL) else {
		throw MessageError("Cannot read PDF: \(path)")
	}
	try unlockPDF(document, password: password, label: path)
	return try makePDFLoader(document: document, sourcePath: path, dpi: dpi)
}

func openPDFFromData(label: String, sourcePath: String?, data: Data, dpi: Int?, password: String?) throws -> ImageLoader {
	guard let provider = CGDataProvider(data: data as CFData),
		let document = CGPDFDocument(provider)
	else {
		throw MessageError("Cannot read PDF from \(label)")
	}
	try unlockPDF(document, password: password, label: label)
	return try makePDFLoader(document: document, sourcePath: sourcePath, dpi: dpi)
}

/// Unlock an encrypted PDF with `password`, or throw a clear error if it stays
/// locked. CGPDFDocument opens an encrypted PDF (non-nil) but page access then
/// fails, which would otherwise surface as a misleading "Could not load PDF
/// page 1". An unencrypted or owner-password-only PDF (`isUnlocked == true`) is
/// left untouched.
func unlockPDF(_ document: CGPDFDocument, password: String?, label: String) throws {
	guard document.isEncrypted, !document.isUnlocked else { return }
	if let password, !password.isEmpty {
		if document.unlockWithPassword(password) { return }
		throw MessageError("Incorrect password for PDF: \(label)")
	}
	throw MessageError("PDF is password protected: \(label). Pass --password <password> or set MAC_OCR_PDF_PASSWORD.")
}

/// Best-effort unlock for a reopened document instance (used by the
/// searchable-pdf render-ahead path). The password is already known to work on
/// the primary instance, so failure is left for the render to surface.
func unlockReopenedPDF(_ document: CGPDFDocument, password: String?) {
	guard let password, !password.isEmpty, document.isEncrypted, !document.isUnlocked else { return }
	_ = document.unlockWithPassword(password)
}

func makePDFLoader(document: CGPDFDocument, sourcePath: String?, dpi: Int?) throws -> ImageLoader {
	let pageCount = document.numberOfPages
	guard pageCount > 0 else {
		throw MessageError("PDF has no pages: \(sourcePath ?? "input")")
	}

	// The caller must ensure `load` is only invoked serially — CGPDFDocument
	// is not thread-safe. BatchRunner iterates serially.
	let colorSpace = CGColorSpaceCreateDeviceRGB()

	return ImageLoader(
		count: pageCount,
		sourcePath: sourcePath,
		load: { pageIndex in
			// PDFs render into a known-upright context, so orientation is always .up
			let image = try renderPDFPage(document: document, pageIndex: pageIndex + 1, colorSpace: colorSpace, requestedDpi: dpi)
			return LoadedImage(image: image, orientation: .up)
		}
	)
}

func isPDFFile(url: URL) -> Bool {
	// Read only the first 1 KB — enough to contain "%PDF-" which appears
	// within the first few bytes of a valid PDF. Cheaper than mmap'ing the
	// whole file and works for PDFs with arbitrary extensions or none.
	guard let handle = try? FileHandle(forReadingFrom: url) else {
		return false
	}
	defer { handle.closeFile() }
	let prefix = handle.readData(ofLength: 1024)
	return isPDFData(prefix)
}

func isPDFData(_ data: Data) -> Bool {
	// PDFs begin with "%PDF-" (optionally after a few bytes of junk).
	// Check the first 1024 bytes to allow for leading whitespace/BOM.
	let prefix = data.prefix(1024)
	guard let marker = "%PDF-".data(using: .ascii) else { return false }
	return prefix.range(of: marker) != nil
}

func renderPDFPage(document: CGPDFDocument, pageIndex: Int, colorSpace: CGColorSpace, requestedDpi: Int?) throws -> CGImage {
	guard let page = document.page(at: pageIndex) else {
		throw MessageError("Could not load PDF page \(pageIndex)")
	}

	// Render the visible page: clip to the CropBox (what a viewer shows) and
	// apply the page's /Rotate, so OCR sees the upright, displayed page rather
	// than cropped-away regions or sideways text.
	let cropBox = page.getBoxRect(.cropBox)
	// Widen to Int before abs: abs(Int32.min) traps, and /Rotate is attacker-controlled.
	let rotated = abs(Int(page.rotationAngle)) % 180 == 90
	let displayWidthPoints = rotated ? cropBox.height : cropBox.width
	let displayHeightPoints = rotated ? cropBox.width : cropBox.height
	// PDF points are 72 per inch, so scale = dpi / 72.
	let dpi: Int
	if let requestedDpi {
		dpi = requestedDpi
	} else {
		// Auto: use the page's largest embedded image to derive the source
		// resolution. Vector-only pages return nil and fall back to the floor.
		let detected = detectSourceDPI(page: page) ?? autoDpiFloor
		dpi = max(autoDpiFloor, min(detected, autoDpiCeiling))
	}
	let scale = CGFloat(dpi) / 72.0
	// Validate as Double first — Int() traps on NaN/infinity/overflow, which
	// would turn a malformed MediaBox into a process crash before the
	// friendly megapixel error had a chance to fire.
	let widthPixels = displayWidthPoints * scale
	let heightPixels = displayHeightPoints * scale
	guard widthPixels.isFinite, heightPixels.isFinite,
		widthPixels > 0, heightPixels > 0
	else {
		throw MessageError("PDF page \(pageIndex) has invalid dimensions")
	}
	let totalPixelsDouble = widthPixels * heightPixels
	let maxPixelsDouble = Double(maxRenderPixels)
	// Reject before the `Int(...)` casts below. Beyond the total-pixel budget,
	// a single oversized dimension can exceed Int.max even when the product
	// would pass (huge width × tiny height), and the product itself can exceed
	// Int64.max — both trap the process on conversion. Neither dimension can
	// legitimately exceed the whole-bitmap pixel budget, so cap each as well.
	// The megapixel figure is computed in Double so the diagnostic never
	// overflows on an absurd MediaBox.
	if !totalPixelsDouble.isFinite
		|| totalPixelsDouble > maxPixelsDouble
		|| widthPixels > maxPixelsDouble
		|| heightPixels > maxPixelsDouble
	{
		let requestedMP = (totalPixelsDouble / 1_000_000).rounded()
		let limitMP = maxRenderPixels / 1_000_000
		throw MessageError(
			"PDF page at \(dpi) DPI would render to \(String(format: "%.0f", requestedMP)) megapixels (max \(limitMP) MP). Try a lower --pdf-dpi.")
	}
	let width = Int(widthPixels)
	let height = Int(heightPixels)

	guard
		let context = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		)
	else {
		throw MessageError("Could not create context for PDF page \(pageIndex)")
	}

	context.setFillColor(CGColor.white)
	context.fill(CGRect(x: 0, y: 0, width: width, height: height))
	context.scaleBy(x: scale, y: scale)
	// Map the CropBox into the display-oriented page rect, applying /Rotate.
	// Content outside the CropBox maps outside the canvas and is clipped.
	let drawingTransform = page.getDrawingTransform(
		.cropBox,
		rect: CGRect(x: 0, y: 0, width: displayWidthPoints, height: displayHeightPoints),
		rotate: 0,
		preserveAspectRatio: false
	)
	context.concatenate(drawingTransform)
	context.drawPDFPage(page)

	guard let image = context.makeImage() else {
		throw MessageError("Could not render PDF page \(pageIndex)")
	}
	return image
}
