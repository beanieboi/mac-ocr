import CoreGraphics
import ImageIO

public struct LoadedImage {
	public let image: CGImage
	public let orientation: CGImagePropertyOrientation
}

extension LoadedImage {
	/// Width in display-oriented space, honoring EXIF orientation (swap for
	/// 90°/270° rotations).
	public var displayWidth: Int {
		swapsDimensions ? image.height : image.width
	}

	public var displayHeight: Int {
		swapsDimensions ? image.width : image.height
	}

	private var swapsDimensions: Bool {
		switch orientation {
		case .left, .leftMirrored, .right, .rightMirrored:
			return true
		default:
			return false
		}
	}
}
