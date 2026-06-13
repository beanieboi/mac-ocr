import Foundation
import Testing

@testable import MacOcrCore

// MARK: - Toy fixtures

private struct ToyPayload: ResultPayload {
	let value: String
	var textOutput: String { value }
}

private func runToy(session: VisionSession) async throws -> ToyPayload {
	ToyPayload(value: "toy-result")
}

// MARK: - Tests

@Suite("BatchRunner")
struct BatchRunnerTests {

	@Test func emptySourcesReturnsImmediately() async throws {
		var called = false
		let strategy = OutputStrategy<ToyPayload> { _, _ in
			called = true
		}
		try await BatchRunner.run(sources: [], output: strategy, runPage: runToy)
		#expect(!called)
	}

	@Test func singleSourceCallsOnResult() async throws {
		let fixture = EngineTestSupport.fixturesURL.appendingPathComponent("hello.png")
		var results: [String] = []
		var pages: [Int] = []

		let strategy = OutputStrategy<ToyPayload> { result, context in
			results.append(result.value)
			pages.append(context.page)
		}

		try await BatchRunner.run(sources: [.file(fixture.path)], output: strategy, runPage: runToy)

		#expect(results == ["toy-result"])
		#expect(pages == [1])
	}

	@Test func pageContextCarriesWidthAndHeight() async throws {
		let fixture = EngineTestSupport.fixturesURL.appendingPathComponent("hello.png")
		var contextWidth = 0
		var contextHeight = 0

		let strategy = OutputStrategy<ToyPayload> { _, context in
			contextWidth = context.width
			contextHeight = context.height
		}

		try await BatchRunner.run(sources: [.file(fixture.path)], output: strategy, runPage: runToy)

		#expect(contextWidth > 0)
		#expect(contextHeight > 0)
	}

	@Test func onSourceDoneCalledAfterEachSource() async throws {
		let fixture = EngineTestSupport.fixturesURL.appendingPathComponent("hello.png")
		var sourceDoneCount = 0
		var resultCount = 0

		let strategy = OutputStrategy<ToyPayload>(
			onResult: { _, _ in resultCount += 1 },
			onSourceDone: { _, _ in sourceDoneCount += 1 }
		)

		try await BatchRunner.run(
			sources: [.file(fixture.path), .file(fixture.path)], output: strategy, runPage: runToy
		)

		#expect(resultCount == 2)
		#expect(sourceDoneCount == 2)
	}

	@Test func onFinishCalledAfterAllSources() async throws {
		let fixture = EngineTestSupport.fixturesURL.appendingPathComponent("hello.png")
		var resultCount = 0
		var finishCount = 0

		let strategy = OutputStrategy<ToyPayload>(
			onResult: { _, _ in resultCount += 1 },
			onFinish: { finishCount += 1 }
		)

		try await BatchRunner.run(sources: [.file(fixture.path)], output: strategy, runPage: runToy)

		#expect(resultCount == 1)
		#expect(finishCount == 1)
	}
}
