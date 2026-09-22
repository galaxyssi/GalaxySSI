import XCTest
@testable import GalaxySSI

final class GalaxySSIEmbeddingRuntimeTests: XCTestCase {
  func testEmbeddingVectorsNormalizeAndCompareFiniteValues() throws {
    let normalized = try GalaxySSIEmbeddingVector.normalized([3, 4])

    XCTAssertEqual(normalized[0], 0.6, accuracy: 0.0001)
    XCTAssertEqual(normalized[1], 0.8, accuracy: 0.0001)
    XCTAssertEqual(try GalaxySSIEmbeddingVector.cosine([3, 4], [6, 8]), 1, accuracy: 0.0001)
  }

  func testEmbeddingVectorsRejectEmptyZeroMismatchedAndNonfiniteValues() {
    XCTAssertThrowsError(try GalaxySSIEmbeddingVector.normalized([]))
    XCTAssertThrowsError(try GalaxySSIEmbeddingVector.normalized([0, 0]))
    XCTAssertThrowsError(try GalaxySSIEmbeddingVector.normalized([.infinity]))
    XCTAssertThrowsError(try GalaxySSIEmbeddingVector.cosine([1], [1, 2]))
  }
}
