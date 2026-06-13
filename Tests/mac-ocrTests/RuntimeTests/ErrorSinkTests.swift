import Foundation
import Testing

@testable import MacOcrCore

@Suite("ErrorSink")
struct ErrorSinkTests {

	@Test func freshSinkHasNoError() async {
		let sink = ErrorSink()
		#expect(await sink.hadError == false)
	}

	@Test func reportStringSetsFlagAndWritesToStderr() async {
		let sink = ErrorSink()
		await sink.report("something went wrong")
		#expect(await sink.hadError == true)
	}

	@Test func reportErrorSetsFlagAndWritesToStderr() async {
		let sink = ErrorSink()
		await sink.report(MessageError("cannot read file"))
		#expect(await sink.hadError == true)
	}

	@Test func multipleReportsKeepFlagSet() async {
		let sink = ErrorSink()
		await sink.report("error one")
		await sink.report("error two")
		#expect(await sink.hadError == true)
	}

	@Test func eachInvocationStartsClean() async {
		// Two separate sinks do not share state
		let sinkA = ErrorSink()
		let sinkB = ErrorSink()
		await sinkA.report("error in A")
		#expect(await sinkA.hadError == true)
		#expect(await sinkB.hadError == false)
	}

	@Test func concurrentReportsAllSetFlag() async {
		let sink = ErrorSink()
		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<8 {
				group.addTask { await sink.report("concurrent error") }
			}
		}
		#expect(await sink.hadError == true)
	}
}
