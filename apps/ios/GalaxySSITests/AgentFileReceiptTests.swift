import XCTest
@testable import GalaxySSI

final class AgentFileReceiptTests: XCTestCase {
  private let transfer = String(repeating: "a", count: 64)
  private func started() -> AgentFileReceipt {
    var receipt = AgentFileReceipt()
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .uploading, fingerprint: "fixture-peer"))
    return receipt
  }
  func testTransportAndModelReadingRemainIndependent() {
    var receipt = started()
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .stored))
    XCTAssertNil(receipt.reading)
    XCTAssertTrue(receipt.report(turn: "original", original: "original", recognized: false))
    XCTAssertEqual(receipt.wire, .stored)
    XCTAssertEqual(receipt.reading, .unreadable)
    var unknown = AgentFileReceipt()
    XCTAssertTrue(unknown.report(turn: "original", original: "original", recognized: true))
    XCTAssertNil(unknown.wire)
    XCTAssertNil(unknown.transfer)
  }
  func testUnknownCannotBecomeStoredOrFailedWithoutInitialTransferBinding() {
    var receipt = AgentFileReceipt()
    XCTAssertFalse(receipt.fold(transfer: transfer, state: .stored))
    XCTAssertFalse(receipt.fold(transfer: transfer, state: .failed))
    XCTAssertFalse(receipt.fold(transfer: transfer, state: .uploading))
    XCTAssertNil(receipt.wire)
  }
  func testReceiptCannotReleaseAnotherTransferOrGeneration() {
    var receipt = started()
    XCTAssertFalse(receipt.fold(transfer: String(repeating: "b", count: 64), state: .stored))
    XCTAssertFalse(receipt.fold(transfer: transfer, state: .stored, generation: 1))
    XCTAssertEqual(receipt.wire, .uploading)
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .failed))
    XCTAssertTrue(receipt.restart(transfer: transfer, fingerprint: "fixture-peer", generation: 1))
    XCTAssertFalse(receipt.fold(transfer: transfer, state: .stored, generation: 0))
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .stored, generation: 1))
  }
  func testRetryRequiresExactNextGenerationAndSamePeerAndConsumesDoubleClick() {
    var receipt = started()
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .failed))
    XCTAssertFalse(receipt.restart(transfer: transfer, fingerprint: "other-peer", generation: 1))
    XCTAssertFalse(receipt.restart(transfer: transfer, fingerprint: "fixture-peer", generation: 2))
    XCTAssertTrue(receipt.restart(transfer: transfer, fingerprint: "fixture-peer", generation: 1))
    XCTAssertFalse(receipt.restart(transfer: transfer, fingerprint: "fixture-peer", generation: 1))
    for generation in 2...3 {
      XCTAssertTrue(receipt.fold(transfer: transfer, state: .failed, generation: generation - 1))
      XCTAssertTrue(receipt.restart(transfer: transfer, fingerprint: "fixture-peer", generation: generation))
    }
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .failed, generation: 3))
    XCTAssertFalse(receipt.restart(transfer: transfer, fingerprint: "fixture-peer", generation: 4))
  }
  func testStoredAndClosedAreTerminalButReceiptReprojectionIsIdempotent() {
    for terminal in [AgentFileReceipt.Wire.stored, .closed] {
      var receipt = started()
      XCTAssertTrue(receipt.fold(transfer: transfer, state: terminal))
      XCTAssertTrue(receipt.fold(transfer: transfer, state: terminal))
      XCTAssertFalse(receipt.fold(transfer: transfer, state: .failed))
      XCTAssertFalse(receipt.restart(transfer: transfer, fingerprint: "fixture-peer", generation: 1))
    }
  }
  func testOnlyCurrentReadTurnCanReportAndRecentClicksCannotStartAgain() {
    var receipt = started()
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .stored))
    XCTAssertTrue(receipt.beginRead(turn: "read-one", now: 100))
    XCTAssertFalse(receipt.beginRead(turn: "read-two", now: 200))
    XCTAssertFalse(receipt.beginRead(turn: "read-two", now: 99))
    XCTAssertFalse(receipt.report(turn: "original", original: "original", recognized: true))
    XCTAssertTrue(receipt.report(turn: "read-one", original: "original", recognized: false))
    XCTAssertTrue(receipt.beginRead(turn: "read-two", now: 30_100))
    XCTAssertFalse(receipt.report(turn: "read-one", original: "original", recognized: true))
    XCTAssertTrue(receipt.report(turn: "read-two", original: "original", recognized: true))
    XCTAssertFalse(receipt.beginRead(turn: "read-three", now: 60_100))
  }
  func testRetryGenerationRejectsBooleanStringFloatNegativeAndExcess() {
    XCTAssertEqual(AgentFileRetryPolicy.generation([:]), 0)
    for number in 0...3 { XCTAssertEqual(AgentFileRetryPolicy.generation(["file_retry_generation": number]), number) }
    let invalid: [Any] = [true, "1", 1.5, -1, 4]
    for bad in invalid { XCTAssertNil(AgentFileRetryPolicy.generation(["file_retry_generation": bad])) }
  }
  func testLegacyReceiptDecodesWithoutInventingFileObservations() throws {
    let receipt = try JSONDecoder().decode(AgentTurnReceipt.self, from: Data("{}".utf8))
    XCTAssertNil(receipt.files)
    XCTAssertNil(receipt.fileReadSource)
  }
}
