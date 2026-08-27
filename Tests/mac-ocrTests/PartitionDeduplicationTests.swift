import Testing

@testable import MacOcrCore

@Suite struct PartitionDeduplicationTests {
	private func observation(
		_ text: String,
		x: Double,
		y: Double,
		width: Double,
		height: Double = 0.012,
		pass: String = "full",
		depth: Int? = nil
	) -> Observation {
		Observation(
			text: text,
			confidence: 1,
			requestRevision: 3,
			boundingBox: BoundingBox(x: x, y: y, width: width, height: height),
			candidates: [],
			source: ObservationSource(pass: pass, depth: depth)
		)
	}

	@Test func completePartitionLineSupersedesEveryOverlappingFragment() {
		let observations = [
			observation("vorbezeichneten", x: 0.35, y: 0.51, width: 0.14),
			observation("Finanzamt", x: 0.50, y: 0.51, width: 0.09),
			observation("der angegebenen Außenstelle", x: 0.70, y: 0.509, width: 0.24),
			observation(
				"Der Einspruch ist bei dem vorbezeichneten Finanzamt oder bei der angegebenen Außenstelle",
				x: 0.10,
				y: 0.509,
				width: 0.84,
				pass: "partition",
				depth: 1
			),
		]

		let supersessions = SearchablePDF.duplicateSupersessions(in: observations)

		#expect(supersessions.count == 3)
		#expect(supersessions[0] == 3)
		#expect(supersessions[1] == 3)
		#expect(supersessions[2] == 3)
	}

	@Test func nearIdenticalReadingsAtSameGeometryAreDuplicates() {
		let full = observation("Rechtsbehe 1 fsbe lehrung", x: 0.098, y: 0.478, width: 0.191)
		let partition = observation(
			"Rechtsbehelfsbe lehrung",
			x: 0.097,
			y: 0.479,
			width: 0.191,
			pass: "partition",
			depth: 2
		)

		#expect(SearchablePDF.isDuplicate(full, partition))
		#expect(SearchablePDF.duplicateSupersessions(in: [full, partition]) == [0: 1])
	}

	@Test func adjacentLinesRemainIndependent() {
		let first = observation("First line of the document", x: 0.10, y: 0.40, width: 0.65)
		let second = observation("Second line of the document", x: 0.10, y: 0.43, width: 0.68)

		#expect(!SearchablePDF.isDuplicate(first, second))
		#expect(SearchablePDF.duplicateSupersessions(in: [first, second]).isEmpty)
	}

	@Test func separateColumnsRemainIndependent() {
		let left = observation("Amount", x: 0.10, y: 0.50, width: 0.15)
		let right = observation("Amount", x: 0.65, y: 0.50, width: 0.15)

		#expect(!SearchablePDF.isDuplicate(left, right))
		#expect(SearchablePDF.duplicateSupersessions(in: [left, right]).isEmpty)
	}
}
