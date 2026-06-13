import Foundation

/// Actor that serializes all Vision request execution.
///
/// The reason this actor exists is GCD dispatch pool exhaustion: at
/// concurrency levels above roughly 32–64 simultaneous Vision requests,
/// Vision's internal work items spawn enough worker threads to exhaust GCD's
/// global concurrent queue limit, causing stalls and silent hangs rather than
/// structured errors. `BatchRunner` already enforces serial execution through
/// a `for source in sources` loop, but `VisionRuntime` promotes that invariant
/// to a compile-time guarantee: the actor's executor runs exactly one call at a
/// time, making pool exhaustion structurally impossible regardless of how many
/// async callers exist.
///
/// (Earlier comments attributed this to ANE deadlock prevention. That framing
/// was inaccurate. The ANE is not a deadlock-prone resource in this usage;
/// GCD pool exhaustion is the empirical failure mode.)
///
/// The closure is deliberately **synchronous**: a sync closure cannot suspend,
/// so actor reentrancy cannot interleave two invocations — the no-overlap
/// guarantee genuinely holds at the type level. Do not add an `async` closure
/// overload: `try await work(session)` suspends inside the actor, the actor is
/// then free to start another call (Swift actors are reentrant), and the
/// serialization this type exists for silently disappears. If an async-native
/// Vision API ever needs serializing, it needs an explicit FIFO gate, not an
/// actor method.
///
/// Callers route every `session.handler.perform([request])` through here:
///
///     let result = try await VisionRuntime.shared.run(session) { session in
///         try recognizeText(in: session, options: options)
///     }
public actor VisionRuntime {
	public static let shared = VisionRuntime()

	/// Execute synchronous Vision work on this actor's serial executor.
	/// Only one invocation of `run` is active at any moment.
	@discardableResult
	public func run<T: Sendable>(
		_ session: VisionSession,
		_ work: @Sendable (VisionSession) throws -> T
	) async rethrows -> T {
		try work(session)
	}
}
