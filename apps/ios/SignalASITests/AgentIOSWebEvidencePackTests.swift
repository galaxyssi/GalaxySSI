import XCTest
@testable import SignalASI

final class AgentIOSWebEvidencePackTests: XCTestCase {
  func testAttachingFetchCreatesCompactUnifiedEvidencePack() throws {
    let content = String(repeating: "Retrieved article evidence for unified model synthesis. ", count: 80)
    let hash = String(repeating: "a", count: 64)
    let attached = AgentIOSWebEvidencePack.attach(
      to: [
        "protocol": .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId),
        "operation": .string("fetch"),
        "status": .string("completed"),
        "url": .string("https://www.example.test/report?utm_source=test"),
        "title": .string("Unified report"),
        "text": .string(content),
        "content_type": .string("text/html"),
        "content_sha256": .string(hash),
        "source_receipts": .array([])
      ],
      generatedAtMillis: 123
    )

    let pack = try XCTUnwrap(attached["evidence_pack"]?.objectValue)
    let document = try XCTUnwrap(attached["documents"]?.arrayValue?.first?.objectValue)
    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)

    XCTAssertEqual(pack["protocol"], .string(AgentIOSWebEvidencePack.protocolId))
    XCTAssertNil(attached["text"])
    XCTAssertNil(document["content"])
    XCTAssertEqual(item["source_kind"], .string("document"))
    XCTAssertEqual(item["evidence_level"], .string("retrieved_body"))
    XCTAssertEqual(item["url"], .string("https://example.test/report"))
    XCTAssertEqual(item["content_sha256"], .string(hash))
    XCTAssertTrue((item["excerpt"]?.stringValue ?? "").contains("Retrieved article evidence"))
  }

  func testRetrievedBodyWinsOverDuplicateDiscoveryResult() throws {
    let pack = AgentIOSWebEvidencePack.build(
      query: "report",
      status: "completed",
      documents: [[
        "url": .string("https://www.example.test/report?utm_source=search"),
        "title": .string("Retrieved report"),
        "content": .string(String(repeating: "Complete retrieved body with verified details. ", count: 40))
      ]],
      results: [[
        "url": .string("https://example.test/report"),
        "title": .string("Search result"),
        "excerpt": .string("Short discovery snippet")
      ]],
      receipts: [],
      generatedAtMillis: 123
    )

    let items = try XCTUnwrap(pack["items"]?.arrayValue)
    let item = try XCTUnwrap(items.first?.objectValue)
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(item["source_kind"], .string("document"))
    XCTAssertTrue((item["excerpt"]?.stringValue ?? "").hasPrefix("Complete retrieved body"))
  }

  func testCitationMatchesCrossPlatformFixture() throws {
    let pack = AgentIOSWebEvidencePack.build(
      query: "fixture",
      status: "completed",
      documents: [[
        "url": .string("https://www.example.com/a?utm_source=x&b=2&a=1"),
        "title": .string("Fixture"),
        "content": .string("Fixture evidence"),
        "content_sha256": .string(String(repeating: "a", count: 64))
      ]],
      results: [],
      receipts: [],
      generatedAtMillis: 1
    )

    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(item["url"], .string("https://example.com/a?a=1&b=2"))
    XCTAssertEqual(item["citation_id"], .string("2a6252e1a64266545ebcf887"))
  }
}
