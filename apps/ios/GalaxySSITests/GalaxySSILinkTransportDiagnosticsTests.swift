import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSILinkTransportDiagnosticsTests: XCTestCase {
  func testGalaxySSILinkDiagnosticLedgerRecordsBoundedEventsAndKeepsLifetimeCounters() {
    var now: Int64 = 1_000
    let ledger = GalaxySSILinkDiagnosticLedger(
      store: InMemoryGalaxySSILinkDiagnosticStore(),
      clockMillis: {
        defer { now += 1_000 }
        return now
      },
      maximumEvents: 2
    )

    ledger.record(
      kind: .encryptedReplay,
      endpointIdentity: "desktop-private-route",
      messageIdentity: "message-1",
      detailCode: "pre decrypt"
    )
    ledger.record(kind: .duplicateMessage, messageIdentity: "message-2")
    let snapshot = ledger.record(kind: .oldCounter, messageIdentity: "message-3")

    XCTAssertEqual(snapshot.totalEvents, 3)
    XCTAssertEqual(snapshot.replayCount, 1)
    XCTAssertEqual(snapshot.duplicateCount, 1)
    XCTAssertEqual(snapshot.oldCounterCount, 1)
    XCTAssertEqual(snapshot.recentEvents.count, 2)
    XCTAssertEqual(snapshot.recentEvents.first?.kind, .oldCounter)
  }

  func testGalaxySSILinkDiagnosticLedgerPersistsAnonymousReferencesAndNormalizedCodes() {
    let store = InMemoryGalaxySSILinkDiagnosticStore()
    let ledger = GalaxySSILinkDiagnosticLedger(store: store, clockMillis: { 1_000 })

    let snapshot = ledger.record(
      kind: .decryptFailure,
      endpointIdentity: "galaxyssi:private-phone-id",
      messageIdentity: "secret-message-id",
      detailCode: "Runtime Exception: private value"
    )
    let persisted = GalaxySSILinkDiagnosticLedger(store: store).snapshot()
    let event = snapshot.recentEvents.singleValue()

    XCTAssertEqual(persisted.totalEvents, 1)
    XCTAssertFalse(event.endpointRef.contains("private"))
    XCTAssertFalse(event.messageRef.contains("secret"))
    XCTAssertEqual(event.endpointRef.count, 12)
    XCTAssertEqual(event.messageRef.count, 12)
    XCTAssertEqual(event.detailCode, "runtime_exception_private_value")
    XCTAssertNotEqual(event.endpointRef, event.messageRef)
  }

  func testGalaxySSILinkTransportDiagnosticsClassifiesDecryptFailures() {
    let oldCounter = NSError(
      domain: "GalaxySSI",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Received message with old counter: 4"]
    )
    let duplicate = DuplicateMessageExceptionForTest()
    let generic = GalaxySSIError.invalidPayload("Malformed Signal body")

    XCTAssertEqual(GalaxySSILinkTransportDiagnostics.classifyDecryptionFailure(oldCounter), .oldCounter)
    XCTAssertEqual(GalaxySSILinkTransportDiagnostics.classifyDecryptionFailure(duplicate), .duplicateMessage)
    XCTAssertEqual(GalaxySSILinkTransportDiagnostics.classifyDecryptionFailure(generic), .decryptFailure)
  }

  func testGalaxySSILinkTransportDiagnosticsClassifiesFragmentFailuresAndWireNames() {
    XCTAssertEqual(
      GalaxySSILinkTransportDiagnostics.classifyFragmentFailure(
        GalaxySSIError.invalidPayload("Conflicting MQTT chunk duplicate")
      ),
      .chunkDuplicate
    )
    XCTAssertEqual(
      GalaxySSILinkTransportDiagnostics.classifyFragmentFailure(
        GalaxySSIError.invalidPayload("MQTT chunk integrity check failed")
      ),
      .fragmentRejected
    )
    XCTAssertEqual(GalaxySSILinkDiagnosticKind.fromWireName("encrypted_replay"), .encryptedReplay)
    XCTAssertNil(GalaxySSILinkDiagnosticKind.fromWireName("unknown"))
    XCTAssertTrue(GalaxySSILinkDiagnosticLedger.anonymizedReference("route").range(
      of: #"^[0-9a-f]{12}$"#,
      options: .regularExpression
    ) != nil)
  }
}

private struct DuplicateMessageExceptionForTest: Error, CustomStringConvertible {
  var description: String {
    "Duplicate message"
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
