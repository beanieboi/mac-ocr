import CoreGraphics
import ImageIO
import Vision

/// A bundle of `(image, orientation, handler)` passed to the recognizer.
/// Building the `VNImageRequestHandler` once per page (rather than once per
/// request) lets multiple Vision requests on the same image reuse it.
// VisionSession crosses into VisionRuntime's actor isolation, so it must be
// Sendable. VNImageRequestHandler is not annotated Sendable (it's Obj-C), but
// the VisionRuntime actor ensures it is never accessed concurrently — all
// handler.perform() calls run on the actor's serial executor.
extension VisionSession: @unchecked Sendable {}

public struct VisionSession {
	public let image: CGImage
	public let orientation: CGImagePropertyOrientation
	public let handler: VNImageRequestHandler

	public init(image: CGImage, orientation: CGImagePropertyOrientation = .up) {
		self.image = image
		self.orientation = orientation
		self.handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
	}
}
