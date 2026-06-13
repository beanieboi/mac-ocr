import CoreGraphics
import Foundation

/// Lazy source of one or more CGImages. `load(pageIndex)` is only called
/// immediately before processing, and the returned image is released after
/// use. This keeps memory bounded even for huge PDFs or large batches.
///
/// `@unchecked Sendable`: the `load` closure may capture a `CGPDFDocument`,
/// which is not thread-safe — the contract (documented on `makePDFLoader`) is
/// that `load` is only ever invoked serially by `BatchRunner`'s source loop.
/// The loader crosses into the output-buffering actor only for its `count`
/// and `sourcePath` metadata.
public struct ImageLoader: @unchecked Sendable {
	public let count: Int
	/// Name used by output routing. Local files keep their path; URL inputs use
	/// a sanitized URL path basename; stdin has no derived output name.
	public let sourcePath: String?
	public let load: (Int) throws -> LoadedImage
}

/// Open an `ImageSource` and return a loader that vends pages on demand.
/// URL sources are downloaded eagerly so that the page count is available
/// immediately (needed for PDF multi-page sources). File and stdin sources
/// decode lazily — no CGImage is held until `load(pageIndex)` is called.
public func openSource(_ source: ImageSource, pdfDpi: Int? = nil, pdfPassword: String? = nil) async throws -> ImageLoader {
	switch source {
	case .file(let path):
		let fileURL = URL(fileURLWithPath: path)
		guard FileManager.default.fileExists(atPath: fileURL.path) else {
			throw MessageError("No such file: \(path)")
		}

		// Detect PDF by magic bytes rather than extension — users may have
		// PDFs with arbitrary filenames, and extension-only detection is
		// fragile. CGPDFDocument on a non-PDF file just returns nil cheaply.
		if isPDFFile(url: fileURL) {
			return try openPDFFromFile(path: path, url: fileURL, dpi: pdfDpi, password: pdfPassword)
		}

		// Lazy decode — don't hold the CGImage until processing is about to run.
		return ImageLoader(
			count: 1,
			sourcePath: path,
			load: { _ in
				guard let loaded = loadImageFromURL(fileURL) else {
					throw MessageError("Cannot read image: \(path)")
				}
				return loaded
			}
		)

	case .url(let urlString):
		guard let remoteURL = URL(string: urlString) else {
			throw MessageError("Invalid URL: \(urlString)")
		}
		let sourcePath = outputSourcePath(for: source)
		// Eager download so we can detect PDFs (need pageCount upfront).
		let data = try await fetchRemoteData(from: remoteURL, label: urlString)
		if isPDFData(data) {
			return try openPDFFromData(label: urlString, sourcePath: sourcePath, data: data, dpi: pdfDpi, password: pdfPassword)
		}
		return ImageLoader(
			count: 1,
			sourcePath: sourcePath,
			load: { _ in
				guard let loaded = loadImageFromData(data) else {
					throw MessageError("Cannot read image from URL: \(urlString)")
				}
				return loaded
			}
		)

	case .stdin:
		let data = try readAllStandardInput()
		guard !data.isEmpty else {
			throw MessageError("No data received on stdin")
		}
		if isPDFData(data) {
			return try openPDFFromData(label: "stdin", sourcePath: nil, data: data, dpi: pdfDpi, password: pdfPassword)
		}
		return ImageLoader(
			count: 1,
			sourcePath: nil,
			load: { _ in
				guard let loaded = loadImageFromData(data) else {
					throw MessageError("Cannot read image from stdin")
				}
				return loaded
			}
		)
	}
}
