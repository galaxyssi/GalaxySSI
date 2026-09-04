import XCTest

@testable import GalaxySSI

final class AgentLargeOutputPolicyTests: XCTestCase {
  func testLargeOutputSplitsAtReadableBoundariesAndReconstructsExactly() {
    var source = ""
    for index in 0..<80 {
      source += "Section \(index)\n"
      source += String(repeating: "content ", count: 180)
      source += "\n\n"
    }

    let prepared = AgentLargeOutputPolicy.prepare(source, includePreview: true)

    XCTAssertGreaterThan(prepared.chunkCount, 1)
    XCTAssertLessThanOrEqual(prepared.storedValue.utf16.count, AgentLargeOutputPolicy.previewCharacters)
    XCTAssertEqual(source, prepared.chunks.joined())
    XCTAssertEqual(source.utf16.count, prepared.totalLength)
    XCTAssertEqual(AgentLargeOutputPolicy.digest(source), prepared.sha256)
  }

  func testDeferredContentDistinguishesPreviewFromHydratedEntry() {
    let source = String(repeating: "long response\n", count: 2_000)
    let prepared = AgentLargeOutputPolicy.prepare(source, includePreview: true)
    let preview = entry(
      text: prepared.storedValue,
      chunkCount: prepared.chunkCount,
      totalLength: prepared.totalLength,
      sha256: prepared.sha256
    )
    var hydrated = preview
    hydrated.text = source

    XCTAssertTrue(AgentLargeOutputPolicy.hasDeferredContent(preview))
    XCTAssertFalse(AgentLargeOutputPolicy.hasDeferredContent(hydrated))
  }

  func testRichOutputDeferredContentUsesAndroidMetadataFields() throws {
    let entry = AgentTranscriptEntry(
      id: "entry",
      role: .assistant,
      text: "",
      timestampMillis: 1,
      richOutputJson: "",
      richOutputChunkCount: 3,
      richOutputLength: 42,
      richOutputSha256: String(repeating: "a", count: 64)
    )

    XCTAssertTrue(AgentLargeOutputPolicy.hasDeferredContent(entry))

    let data = try JSONEncoder().encode(entry)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(object?["rich_output_chunk_count"] as? Int, 3)
    XCTAssertEqual(object?["rich_output_length"] as? Int, 42)
    XCTAssertEqual(object?["rich_output_sha256"] as? String, String(repeating: "a", count: 64))
  }

  func testChunkAndPreviewBoundariesPreserveNonBMPCharacters() {
    let source = String(repeating: "a", count: AgentLargeOutputPolicy.chunkCharacters - 1) +
      "\u{1F680}" +
      String(repeating: "b", count: AgentLargeOutputPolicy.chunkThresholdCharacters)

    let prepared = AgentLargeOutputPolicy.prepare(source, includePreview: true)

    XCTAssertFalse(isHighSurrogate(prepared.storedValue.utf16.last))
    for chunk in prepared.chunks {
      XCTAssertFalse(isHighSurrogate(chunk.utf16.last))
      XCTAssertFalse(isLowSurrogate(chunk.utf16.first))
    }
    XCTAssertEqual(source, prepared.chunks.joined())
    XCTAssertEqual(AgentLargeOutputPolicy.digest(source), prepared.sha256)
  }

  func testShortOutputStoresInlineWithDigestAndLength() {
    let source = "abc"

    let prepared = AgentLargeOutputPolicy.prepare(source, includePreview: false)

    XCTAssertEqual(source, prepared.storedValue)
    XCTAssertTrue(prepared.chunks.isEmpty)
    XCTAssertEqual(3, prepared.totalLength)
    XCTAssertEqual("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", prepared.sha256)
  }

  private func entry(
    text: String,
    chunkCount: Int,
    totalLength: Int,
    sha256: String
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: "entry",
      role: .assistant,
      text: text,
      timestampMillis: 1,
      conversationId: "conversation",
      textChunkCount: chunkCount,
      textLength: totalLength,
      textSha256: sha256
    )
  }

  private func isHighSurrogate(_ value: UInt16?) -> Bool {
    guard let value else {
      return false
    }
    return (0xD800...0xDBFF).contains(value)
  }

  private func isLowSurrogate(_ value: UInt16?) -> Bool {
    guard let value else {
      return false
    }
    return (0xDC00...0xDFFF).contains(value)
  }
}
