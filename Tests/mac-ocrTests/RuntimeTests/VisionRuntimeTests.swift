import Foundation
import Testing

@testable import MacOcrCore

@Suite("VisionRuntime")
struct VisionRuntimeTests {

	// MARK: Round-trip

	@Test func syncRunReturnsResult() async throws {
		let loaded = try EngineTestSupport.loadImage("empty.png")
		let session = VisionSession(image: loaded.image, orientation: loaded.orientation)

		let result = await VisionRuntime.shared.run(session) { _ in 42 }
		#expect(result == 42)
	}

	@Test func syncRunPropagatesError() async throws {
		let loaded = try EngineTestSupport.loadImage("empty.png")
		let session = VisionSession(image: loaded.image, orientation: loaded.orientation)

		await #expect(throws: MessageError.self) {
			try await VisionRuntime.shared.run(session) { _ in
				throw MessageError("test error")
			}
		}
	}

	// MARK: Serialization
	//
	// The closure is synchronous by design: it cannot suspend, so actor
	// reentrancy cannot interleave two invocations — the no-overlap invariant
	// genuinely holds at the type level. (An async-closure overload would
	// break this silently; see the note on VisionRuntime itself.) The test
	// below confirms concurrent callers all complete without deadlock or
	// data loss.

	@Test func concurrentCallsAllComplete() async throws {
		let loaded = try EngineTestSupport.loadImage("empty.png")
		let session = VisionSession(image: loaded.image, orientation: loaded.orientation)

		let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
			for index in 0..<8 {
				group.addTask {
					await VisionRuntime.shared.run(session) { _ in index }
				}
			}
			var collected: [Int] = []
			for await value in group {
				collected.append(value)
			}
			return collected
		}

		#expect(results.count == 8)
		#expect(Set(results) == Set(0..<8))
	}

	@Test func sharedSingletonIsTheSameInstance() {
		// Both references must point to the same actor to guarantee global
		// serialization. Two distinct VisionRuntime instances would not serialize
		// against each other.
		#expect(VisionRuntime.shared === VisionRuntime.shared)
	}
}
