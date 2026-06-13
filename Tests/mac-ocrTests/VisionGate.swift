import Foundation

/// Global binary semaphore that serialises all Vision / ANE access across test
/// suites and across the subprocess / in-process boundary.
///
/// Swift Testing runs different top-level @Suite types concurrently. Vision pins
/// the Apple Neural Engine (ANE), a shared resource that deadlocks under
/// concurrent load. Additionally, spawning many concurrent mac-ocr subprocesses
/// exhausts the global DispatchQueue thread pool (two pipe-reading tasks per
/// process) causing group.wait() to stall even after the subprocesses exit.
///
/// All test code that touches Vision must flow through this gate:
///   - Subprocess invocations go through TestSupport.run().
///   - Direct engine calls go through engine test suite init/deinit.
///
/// Using a continuation queue rather than NSLock makes the gate safe to
/// acquire from async test functions without blocking cooperative threads.
final class VisionGate: @unchecked Sendable {
	static let shared = VisionGate()

	/// Serial queue used as a lightweight mutex for state mutations.
	private let queue = DispatchQueue(label: "com.privatenumber.mac-ocr.tests.VisionGate")
	private var available = true
	private var waiters: [CheckedContinuation<Void, Never>] = []

	private init() {}

	/// Async acquire — suspends the caller until the gate is free. Safe to call
	/// from async test functions; does not block any cooperative thread.
	func acquire() async {
		await withCheckedContinuation { continuation in
			queue.sync {
				if self.available {
					self.available = false
					continuation.resume()
				} else {
					self.waiters.append(continuation)
				}
			}
		}
	}

	/// Test-only introspection: how many acquirers are currently queued.
	/// Lets ordering tests enqueue waiters deterministically (poll until the
	/// previous waiter is registered) instead of racing timed sleeps.
	var waiterCount: Int {
		queue.sync { waiters.count }
	}

	/// Release — wakes the next waiter if any. May be called from any context.
	func release() {
		queue.async {
			if self.waiters.isEmpty {
				self.available = true
			} else {
				self.waiters.removeFirst().resume()
			}
		}
	}

	/// Blocking acquire for synchronous (non-async) test contexts. Spawns a
	/// detached task to perform the async acquire, then waits on a semaphore.
	/// Only call this from OS threads — never from async / cooperative contexts.
	func acquireBlocking() {
		let sema = DispatchSemaphore(value: 0)
		Task.detached { [self] in
			await self.acquire()
			sema.signal()
		}
		sema.wait()
	}
}
