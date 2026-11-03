import XCTest
@testable import GalaxySSI

final class MqttDeliveryEnvelopeTests: XCTestCase {
  private let sender = String(repeating: "a", count: 64)
  private let receiver = String(repeating: "b", count: 64)

  func testAndroidSharedGoldenDigests() throws {
    XCTAssertEqual(try MqttDeliveryEnvelope.contentHash(wire()),
                   "d8d7f88a7543d8bd82fc4d7c364283923a15752ba6d1f23af4903d19a544d581")
    let unicode: [String: Any] = ["scheme": "signal", "from": "\u{624b}\u{673a}-A", "to": "\u{7535}\u{8111}-B",
      "signal_type": "signal", "message_type": 2, "body": "AA==", "device_id": 1, "version": 1]
    XCTAssertEqual(try MqttDeliveryEnvelope.contentHash(unicode),
                   "94c78f615ab4f6d1e8120091f1d0e25f57eeb4b2beb94833b1b6507f957f2d3c")
  }

  func testMutableTimeAndAttemptDoNotChangeHash() throws {
    var changed = wire()
    changed["time"] = 1.25
    changed[MqttDeliveryEnvelope.field] = ["unknown": true]
    XCTAssertEqual(try MqttDeliveryEnvelope.contentHash(changed), try MqttDeliveryEnvelope.contentHash(wire()))
  }

  func testEveryRecognizedSignalFieldChangesHash() throws {
    let complete: [String: Any] = wire().merging(["type": "cipher", "protocol": "galaxyssi", "messageType": 3, "device_id": 1]) { _, new in new }
    let original = try MqttDeliveryEnvelope.contentHash(complete)
    for (key, value) in complete {
      var changed = complete
      if let text = value as? String { changed[key] = text + "-changed" }
      else { changed[key] = 42 }
      if key == "scheme" { XCTAssertThrowsError(try MqttDeliveryEnvelope.contentHash(changed)) }
      else { XCTAssertNotEqual(try MqttDeliveryEnvelope.contentHash(changed), original, key) }
    }
  }

  func testFrameAndStoredReceiptRoundTripWithoutMutatingWire() throws {
    let original = wire()
    let frame = try frame()
    XCTAssertEqual(try parse(frame.attach(to: original)), frame)
    XCTAssertNil(original[MqttDeliveryEnvelope.field])
    let receipt = try frame.receiptAfterStore(messageID: frame.message.messageID, wireHash: frame.message.contentHash)
    XCTAssertEqual(try MqttDeliveryEnvelope.parseVerifiedReceipt(receipt, originalSender: sender, originalReceiver: receiver), frame)
    let stored = try MqttDeliveryEnvelope.storedReceipt(messageID: "message-1", wireHash: frame.message.contentHash)
    let parsed = try MqttDeliveryEnvelope.parseStoredReceipt(stored)
    XCTAssertEqual(parsed.messageID, "message-1")
    XCTAssertEqual(parsed.wireHash, frame.message.contentHash)
  }

  func testMetadataCannotOverrideAuthenticatedPairOrActualIngress() throws {
    let attached = try frame().attach(to: wire())
    for (source, target, broker) in [(receiver, sender, "hivemq"), (sender, sender, "hivemq"), (sender, receiver, "emqx")] {
      XCTAssertThrowsError(try MqttDeliveryEnvelope.parseVerifiedFrame(attached, sender: source, receiver: target, ingressBroker: broker))
    }
  }

  func testTamperingAndDoubleWrappingAreRejected() throws {
    let frame = try frame()
    var attached = try frame.attach(to: wire())
    XCTAssertThrowsError(try frame.attach(to: attached))
    attached["body"] = "AA=="
    XCTAssertThrowsError(try parse(attached))
  }

  func testOnlyMatchingCommittedRecordCanProduceReceipt() throws {
    let frame = try frame()
    XCTAssertThrowsError(try frame.receiptAfterStore(messageID: "other", wireHash: frame.message.contentHash))
    XCTAssertThrowsError(try frame.receiptAfterStore(messageID: "message-1", wireHash: String(repeating: "d", count: 64)))
    let receiptFrame = try self.frame(traffic: "receipt")
    XCTAssertThrowsError(try receiptFrame.receiptAfterStore(messageID: "message-1", wireHash: receiptFrame.message.contentHash))
    var unsolicited = receiptFrame.metadata()
    unsolicited["type"] = MqttDeliveryEnvelope.receiptType
    unsolicited["status"] = "RX_STORED"
    XCTAssertThrowsError(try MqttDeliveryEnvelope.parseVerifiedReceipt(unsolicited, originalSender: sender, originalReceiver: receiver))
  }

  func testStrictMetadataValues() throws {
    let invalid: [String: [Any]] = [
      "generation": [true, 1.0, Float(1), 1.5, "7", 0, -1, Int64(9_007_199_254_740_992)],
      "version": [true, 1.0, 1.5, "1", 2], "broker_id": ["unknown", NSNull()],
      "traffic": ["unknown", NSNull()], "attempt_id": ["", String(repeating: "C", count: 32)],
      "content_hash_algorithm": ["sha256", NSNull()], "message_id": ["", "bad\n", String(repeating: "x", count: 257)]
    ]
    for (key, values) in invalid {
      for value in values {
        var attached = try frame().attach(to: wire())
        var metadata = try XCTUnwrap(attached[MqttDeliveryEnvelope.field] as? [String: Any])
        metadata[key] = value
        attached[MqttDeliveryEnvelope.field] = metadata
        XCTAssertThrowsError(try parse(attached), "\(key): \(value)")
      }
    }
  }

  func testHashRejectsInvalidSignalNumbersTextAndByteLimits() {
    let invalidNumbers: [Any] = [true, 1.0, 1.5, "3", 0, -1, NSNull()]
    for value in invalidNumbers {
      var changed = wire()
      changed["message_type"] = value
      XCTAssertThrowsError(try MqttDeliveryEnvelope.contentHash(changed))
    }
    for value in ["", "bad\u{7f}", "bad\0", String(repeating: "\u{1f680}", count: 129)] {
      var changed = wire()
      changed["from"] = value
      XCTAssertThrowsError(try MqttDeliveryEnvelope.contentHash(changed))
    }
    var tooLarge = wire()
    tooLarge["body"] = String(repeating: "x", count: 4 * 1024 * 1024 + 1)
    XCTAssertThrowsError(try MqttDeliveryEnvelope.contentHash(tooLarge))
  }

  func testBrokerAndTaskStatusCannotMasqueradeAsStorageReceipt() throws {
    let frame = try frame()
    for status in ["accepted", "BROKER_ACKED", "CHUNK_STORED", "TASK_ACCEPTED", "RUN_FINISHED", ""] {
      var receipt = try MqttDeliveryEnvelope.storedReceipt(messageID: "message-1", wireHash: frame.message.contentHash)
      receipt["delivery_status"] = status
      XCTAssertThrowsError(try MqttDeliveryEnvelope.parseStoredReceipt(receipt))
      var transport = try frame.receiptAfterStore(messageID: "message-1", wireHash: frame.message.contentHash)
      transport["status"] = status
      XCTAssertThrowsError(try MqttDeliveryEnvelope.parseVerifiedReceipt(transport, originalSender: sender, originalReceiver: receiver))
    }
  }

  func testAllRelationshipComponentsFenceReceiptsAndLengthsPreventAliasing() throws {
    let values = ["pair", sender, receiver, "secret"]
    func binding(_ v: [String]) throws -> String {
      try MqttDeliveryEnvelope.receiptBinding(scope: v[0], sender: v[1], receiver: v[2], secret: v[3])
    }
    for index in values.indices {
      var changed = values
      changed[index] += "x"
      XCTAssertNotEqual(try binding(values), try binding(changed))
    }
    XCTAssertNotEqual(try binding(["ab", "c", "d", "e"]), try binding(["a", "bc", "d", "e"]))
  }

  private func wire() -> [String: Any] {
    ["scheme": "signal", "from": "phone-A", "to": "desktop-B", "signal_type": "prekey",
     "message_type": 3, "body": "AQIDBA==", "version": 1]
  }

  private func frame(traffic: String = "message") throws -> MqttDeliveryEnvelope.Frame {
    try .init(message: .init(messageID: "message-1", contentHash: MqttDeliveryEnvelope.contentHash(wire()),
                            sender: sender, receiver: receiver, traffic: traffic),
              attempt: .init(attemptID: String(repeating: "c", count: 32), brokerID: "hivemq", generation: 7))
  }

  private func parse(_ wire: [String: Any]) throws -> MqttDeliveryEnvelope.Frame {
    try MqttDeliveryEnvelope.parseVerifiedFrame(wire, sender: sender, receiver: receiver, ingressBroker: "hivemq")
  }
}
