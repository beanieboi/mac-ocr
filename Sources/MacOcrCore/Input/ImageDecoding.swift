import CoreGraphics
import Foundation
import ImageIO

func loadImageFromURL(_ url: URL) -> LoadedImage? {
	guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
		return nil
	}
	return loadedImage(from: source)
}

func loadImageFromData(_ data: Data) -> LoadedImage? {
	guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
		return nil
	}
	return loadedImage(from: source)
}

func loadedImage(from source: CGImageSource) -> LoadedImage? {
	guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
		return nil
	}
	return LoadedImage(image: image, orientation: readOrientation(from: source))
}

func readOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
	guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
		let raw = properties[kCGImagePropertyOrientation] as? UInt32,
		let orientation = CGImagePropertyOrientation(rawValue: raw)
	else {
		return .up
	}
	return orientation
}
