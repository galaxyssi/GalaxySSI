import XCTest
@testable import GalaxySSI

final class MqttChunkProtocolTests: XCTestCase {
  func testManifestIsStableAcrossFragmentsAndBindsEndpoints() throws {
    let packets = try chunks()
    let first = try MqttChunkManifest.parse(packets[0])
    let second = try MqttChunkManifest.parse(packets[1])
    XCTAssertEqual(first.manifestHash, second.manifestHash)
    XCTAssertNotEqual(first.digest, second.digest)
    for key in ["from", "to"] {
      var changed = packets[0]
      changed[key] = "changed"
      XCTAssertNotEqual(try MqttChunkManifest.parse(changed).manifestHash, first.manifestHash)
    }
  }

  func testManifestRejectsCoercionAndNoncanonicalHashesAndBase64() throws {
    let packet = try chunks()[0]
    let invalid: [String: [Any]] = [
      "chunk_count": [true, 2.0, 2.5, "2", 0, 97], "chunk_index": [true, 0.0, 0.5, "0", -1, 96],
      "total_bytes": [true, "100", 0, MqttChunkManifest.maximumBytes + 1],
      "from": ["", "bad\n", String(repeating: "x", count: 513)],
      "transfer_id": [String(repeating: "A", count: 64), "bad"],
      "chunk_sha256": [String(repeating: "g", count: 64)], "data": ["", "Zh==", "Zg==\n", "####", NSNull()]
    ]
    for (key, values) in invalid {
      for value in values {
        var changed = packet
        changed[key] = value
        XCTAssertThrowsError(try MqttChunkManifest.parse(changed), "\(key): \(value)")
      }
    }
  }

  func testChunkRequestMustMatchItsActualManifest() throws {
    var packet = try chunks()[0]
    XCTAssertNil(try MqttChunkReceipts.fromChunk(packet))
    let query = try query(for: packet)
    packet[MqttChunkReceipts.field] = query.wire()
    XCTAssertEqual(try MqttChunkReceipts.fromChunk(packet), query)
    var mismatch = query.wire()
    mismatch["manifest_hash"] = String(repeating: "0", count: 64)
    packet[MqttChunkReceipts.field] = mismatch
    XCTAssertThrowsError(try MqttChunkReceipts.fromChunk(packet))
    packet[MqttChunkReceipts.field] = NSNull()
    XCTAssertThrowsError(try MqttChunkReceipts.fromChunk(packet))
  }

  func testBitmapUsesAndroidLeastSignificantBitOrderAcrossByteBoundary() throws {
    let query = try MqttChunkReceipts.Query(transfer: String(repeating: "a", count: 64),
      manifest: String(repeating: "b", count: 64), count: 10, request: String(repeating: "c", count: 32))
    let wire = try query.response(epoch: String(repeating: "d", count: 32), revision: 2, indices: [0, 7, 8, 9])
    let state = try MqttChunkReceipts.parseState(wire)
    XCTAssertEqual(state.bitmap, Data([0x81, 0x03]))
    XCTAssertEqual(wire["stored_bitmap"] as? String, "gQM=")
    XCTAssertEqual(state.storedIndices, [0, 7, 8, 9])
    XCTAssertEqual(state.query, query)
  }

  func testBitmapRejectsPaddingBitsWrongSizeAndInvalidEpochState() throws {
    let query = try MqttChunkReceipts.Query(transfer: String(repeating: "a", count: 64),
      manifest: String(repeating: "b", count: 64), count: 10, request: String(repeating: "c", count: 32))
    let valid = try query.response(epoch: String(repeating: "d", count: 32), revision: 2, indices: [0])
    let invalid: [(String, Any)] = [("stored_bitmap", Data([1, 4]).base64EncodedString()),
      ("stored_bitmap", Data([1]).base64EncodedString()), ("revision", true), ("revision", -1),
      ("revision", 1.5), ("revision", "2"), ("store_epoch", String(repeating: "D", count: 32))]
    for (key, value) in invalid {
      var changed = valid
      changed[key] = value
      XCTAssertThrowsError(try MqttChunkReceipts.parseState(changed))
    }
    let zero = String(repeating: "0", count: 32)
    XCTAssertNoThrow(try query.response(epoch: zero, revision: 0, indices: []))
    XCTAssertThrowsError(try query.response(epoch: zero, revision: 1, indices: []))
    XCTAssertThrowsError(try query.response(epoch: zero, revision: 0, indices: [0]))
    XCTAssertThrowsError(try query.response(epoch: zero, revision: 0, indices: [10]))
  }

  func testMaximumBitmapCountAndCounters() throws {
    let query = try MqttChunkReceipts.Query(transfer: String(repeating: "a", count: 64),
      manifest: String(repeating: "b", count: 64), count: 96, request: String(repeating: "c", count: 32))
    let state = try MqttChunkReceipts.parseState(query.response(epoch: String(repeating: "d", count: 32),
      revision: MqttRouteProtocol.maximumInteger, indices: Set(0..<96)))
    XCTAssertEqual(state.bitmap, Data(repeating: 255, count: 12))
    XCTAssertEqual(state.storedIndices.count, 96)
    var bad = query.wire()
    bad["version"] = true
    XCTAssertThrowsError(try MqttChunkReceipts.parse(bad))
  }

  func testExistingAssemblerUsesStrictManifestValidation() throws {
    let packet = try chunks()[0]
    let assembler = GalaxySSIMqttChunkAssembler()
    let invalid: [Any] = [true, "2", 2.5]
    for value in invalid {
      var changed = packet
      changed["chunk_count"] = value
      XCTAssertThrowsError(try assembler.accept(scope: "pair", wire: changed))
    }
    XCTAssertNil(try assembler.accept(scope: "pair", wire: packet))
  }

  func testAssemblerRejectsEndpointMismatchAfterReassembly() throws {
    let packets = try chunks()
    let assembler = GalaxySSIMqttChunkAssembler()
    for (index, packet) in packets.enumerated() {
      var changed = packet
      changed["from"] = "forged-source"
      if index == packets.count - 1 { XCTAssertThrowsError(try assembler.accept(scope: "pair", wire: changed)) }
      else { XCTAssertNil(try assembler.accept(scope: "pair", wire: changed)) }
    }
  }

  func testAssemblerRejectsAggregateSizeBeforeRetainingMoreFragments() throws {
    let packets = try chunks()
    let assembler = GalaxySSIMqttChunkAssembler()
    var first = packets[0]
    var second = packets[1]
    first["total_bytes"] = 30
    second["total_bytes"] = 30
    XCTAssertNil(try assembler.accept(scope: "pair", wire: first))
    XCTAssertThrowsError(try assembler.accept(scope: "pair", wire: second))
  }

  func testOneChunkManifestAndFullRoundTripMatchAndroid() throws {
    let bytes = Data(#"{"scheme":"signal","from":"a","to":"b","body":"AA=="}"#.utf8)
    let digest = MqttRouteProtocol.digest(bytes)
    let wire: [String: Any] = ["scheme": "signal-chunk", "transfer_id": digest, "sha256": digest,
      "chunk_sha256": digest, "chunk_count": 1, "chunk_index": 0, "total_bytes": bytes.count,
      "from": "a", "to": "b", "data": bytes.base64EncodedString()]
    XCTAssertEqual(digest, "0c786f17779d7d37fee6df7e4ef55573c83d6caba3316b27eb55f7e09e702fa3")
    XCTAssertEqual(try MqttChunkManifest.parse(wire).manifestHash,
                   "ff8505984c29945de0b7f169674454e01d974f4a4d0674001e85072b2163ac0a")
    XCTAssertEqual(try GalaxySSIMqttChunkAssembler().accept(scope: "pair", wire: wire), String(data: bytes, encoding: .utf8))
    let assembler = GalaxySSIMqttChunkAssembler()
    let packets = try chunks()
    var assembled: String?
    for packet in packets.reversed() { assembled = try assembler.accept(scope: "pair", wire: packet) }
    XCTAssertEqual(assembled, original())
  }

  private func original() -> String { #"{"scheme":"signal","from":"phone-A","to":"desktop-B","body":"AQIDBA==","version":1}"# }

  private func chunks() throws -> [[String: Any]] {
    try GalaxySSIMqttWireChunking.encode(wirePayload: original(), directLimitBytes: 1, chunkDataBytes: 24).map {
      try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
    }
  }

  private func query(for packet: [String: Any]) throws -> MqttChunkReceipts.Query {
    let chunk = try MqttChunkManifest.parse(packet)
    return try .init(transfer: chunk.transfer, manifest: chunk.manifestHash, count: chunk.count,
                     request: String(repeating: "c", count: 32))
  }
}
