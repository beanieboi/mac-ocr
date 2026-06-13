import CoreGraphics

/// Walks the page's image XObjects and returns the highest effective source
/// DPI — `imagePixels / pageInches`. Returns nil for vector-only pages or
/// when dimensions are unreadable. Recurses through Form XObjects so that
/// scanned PDFs (e.g. Acrobat OCR output) where the page image is wrapped
/// in a Form XObject are still detected.
func detectSourceDPI(page: CGPDFPage) -> Int? {
	let mediaBox = page.getBoxRect(.mediaBox)
	let pageWidthInches = mediaBox.width / 72.0
	let pageHeightInches = mediaBox.height / 72.0
	guard pageWidthInches > 0, pageHeightInches > 0 else { return nil }

	var images: [(width: Int, height: Int)] = []
	var visited = Set<Int>()
	collectImageDimensions(from: page.dictionary, into: &images, visited: &visited)
	guard !images.isEmpty else { return nil }

	// Accumulate in Double. A near-zero (but positive) MediaBox dimension makes
	// pixels-per-inch enormous — potentially past Int.max or infinite — so
	// converting each ratio straight to Int (as before) traps the process on a
	// malformed page, before `renderPDFPage`'s own guards run. Skip non-finite
	// ratios and clamp to `autoDpiCeiling` before the single Int conversion. The
	// caller already clamps the detected DPI to `autoDpiCeiling`, so bounding it
	// here only removes the overflow without changing any real-page result.
	var maxDpi = 0.0
	for (width, height) in images {
		let dpiX = Double(width) / pageWidthInches
		let dpiY = Double(height) / pageHeightInches
		if dpiX.isFinite {
			maxDpi = max(maxDpi, dpiX)
		}
		if dpiY.isFinite {
			maxDpi = max(maxDpi, dpiY)
		}
	}
	guard maxDpi > 0 else { return nil }
	let detectedDpi = Int(min(maxDpi, Double(autoDpiCeiling)).rounded())
	return detectedDpi > 0 ? detectedDpi : nil
}

/// Walks `dict.Resources.XObject`, appending Image XObject dimensions to
/// `images`. For Form XObjects, recurses into their own Resources. `visited`
/// tracks dictionary pointers to guard against cyclic references.
private func collectImageDimensions(
	from dict: CGPDFDictionaryRef?,
	into images: inout [(width: Int, height: Int)],
	visited: inout Set<Int>
) {
	guard let dict else { return }
	let dictKey = unsafeBitCast(dict, to: Int.self)
	if !visited.insert(dictKey).inserted { return }

	var resources: CGPDFDictionaryRef?
	guard CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources else { return }
	var xobjects: CGPDFDictionaryRef?
	guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return }

	// Gather the streams into a Swift array first, then recurse outside the
	// C apply-block (which can't call Swift functions with inout parameters).
	var streams: [CGPDFStreamRef] = []
	withUnsafeMutablePointer(to: &streams) { streamsPtr in
		CGPDFDictionaryApplyBlock(
			xobjects,
			{ _, value, info in
				var stream: CGPDFStreamRef?
				guard CGPDFObjectGetValue(value, .stream, &stream), let stream else { return true }
				let collector = info!.assumingMemoryBound(to: [CGPDFStreamRef].self)
				collector.pointee.append(stream)
				return true
			}, UnsafeMutableRawPointer(streamsPtr))
	}

	for stream in streams {
		guard let streamDict = CGPDFStreamGetDictionary(stream) else { continue }
		var subtypePtr: UnsafePointer<Int8>?
		guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtypePtr), let subtypePtr else { continue }
		let subtype = String(cString: subtypePtr)

		if subtype == "Image" {
			var width: CGPDFInteger = 0
			var height: CGPDFInteger = 0
			CGPDFDictionaryGetInteger(streamDict, "Width", &width)
			CGPDFDictionaryGetInteger(streamDict, "Height", &height)
			images.append((Int(width), Int(height)))
		} else if subtype == "Form" {
			collectImageDimensions(from: streamDict, into: &images, visited: &visited)
		}
	}
}
