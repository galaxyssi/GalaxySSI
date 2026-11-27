import CryptoKit
import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryCopyStateTests: XCTestCase {
  private var source: AgentKnowledgePrimaryPartitions.Reference {
    .init(version: 1, partition: UUID().uuidString.lowercased(), entry: UUID().uuidString.lowercased(), frames: 33,
      plainBytes: 32 * 65_536 + 17, sha256: String(repeating: "a", count: 64))
  }
  func testEmptyStateRoundTripsAndRejectsFutureVersions() throws {
    let old = source, state = AgentKnowledgePrimaryCopyState()
    try state.validate(old)
    var reopened = try JSONDecoder().decode(AgentKnowledgePrimaryCopyState.self, from: JSONEncoder().encode(state))
    try reopened.validate(old)
    XCTAssertEqual(reopened.entry, state.entry)
    reopened.version = 2; XCTAssertThrowsError(try reopened.validate(old))
  }
  func testCopiedAndVerifiedCursorsRequireExactPrefixByteCounts() throws {
    let old = source
    var state = AgentKnowledgePrimaryCopyState()
    state.copied = 16; state.copiedPlainBytes = 16 * 65_536; state.storedBytes = 16
    try state.validate(old)
    state.copiedPlainBytes -= 1; XCTAssertThrowsError(try state.validate(old))
    state.copiedPlainBytes += 1; state.copied = 34; XCTAssertThrowsError(try state.validate(old))
    state.copied = 16; state.verified = 1; state.verifiedPlainBytes = 65_536
    XCTAssertThrowsError(try state.validate(old))
  }
  func testFinalFrameUsesExactShortLengthAndVerificationCannotLeadCopy() throws {
    let old = source
    var state = AgentKnowledgePrimaryCopyState()
    state.copied = 33; state.copiedPlainBytes = old.plainBytes; state.storedBytes = 33
    state.verified = 32; state.verifiedPlainBytes = 32 * 65_536
    try state.validate(old)
    state.verified = 33; state.verifiedPlainBytes = old.plainBytes
    try state.validate(old)
    state.verifiedPlainBytes += 1; XCTAssertThrowsError(try state.validate(old))
    state.verified = 34; XCTAssertThrowsError(try state.validate(old))
  }
  func testCiphertextAccountingAndEmptyHashSentinelsFailClosed() throws {
    let old = source
    var state = AgentKnowledgePrimaryCopyState()
    state.storedBytes = 1; XCTAssertThrowsError(try state.validate(old))
    state.storedBytes = 0; state.copiedHash = String(repeating: "a", count: 64)
    XCTAssertThrowsError(try state.validate(old))
    state.copiedHash = AgentKnowledgePrimaryCopyState.emptyHash; state.verifiedHash = "bad"
    XCTAssertThrowsError(try state.validate(old))
    state.verifiedHash = AgentKnowledgePrimaryCopyState.emptyHash; state.entry = old.entry
    XCTAssertThrowsError(try state.validate(old))
  }
  func testChainBindsPreviousDigestOrdinalAndExactCompressedBytes() throws {
    let zero = AgentKnowledgePrimaryCopyState.emptyHash, frame = Data("frame".utf8)
    var expected = Data(repeating: 0, count: 40); expected.append(frame)
    let hash = try AgentKnowledgePrimaryCopyState.chain(zero, ordinal: 0, encoded: frame)
    XCTAssertEqual(hash, SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined())
    XCTAssertNotEqual(hash, try AgentKnowledgePrimaryCopyState.chain(zero, ordinal: 1, encoded: frame))
    XCTAssertNotEqual(hash, try AgentKnowledgePrimaryCopyState.chain(hash, ordinal: 0, encoded: frame))
    XCTAssertNotEqual(hash, try AgentKnowledgePrimaryCopyState.chain(zero, ordinal: 0, encoded: Data("changed".utf8)))
    XCTAssertThrowsError(try AgentKnowledgePrimaryCopyState.chain("bad", ordinal: 0, encoded: frame))
  }
  func testStorageBudgetDistinguishesCooperativeYieldFromInvalidClock() throws {
    var now: TimeInterval = 1
    let budget = AgentKnowledgeStorageMaintenanceBudget(seconds: 1, clock: { now })
    now = 2
    XCTAssertThrowsError(try budget.check()) { XCTAssertTrue($0 is AgentKnowledgeStorageYield) }
    now = 0
    XCTAssertThrowsError(try budget.check()) { XCTAssertTrue($0 is CancellationError) }
  }
}
