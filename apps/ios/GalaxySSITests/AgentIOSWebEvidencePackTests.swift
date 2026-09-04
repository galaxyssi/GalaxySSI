import XCTest
@testable import GalaxySSI

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

  func testModelAuthoredResearchPlanIsBoundedNormalizedAndDeduplicated() {
    let plan = AgentIOSWebResearchPlanCodec.decode(
      primaryQuery: "fallback",
      rawPlan: .array([
        .object([
          "query": .string("  Swift   concurrency updates  "),
          "purpose": .string(" Verify current behavior "),
          "verticals": .array([.string("DOCS"), .string("unsupported")]),
          "categories": .array([.string(" Apple Platforms "), .string("***")]),
          "engines": .array([.string("Engine-One"), .string("bad engine"), .string("engine-one")])
        ]),
        .string("swift concurrency updates")
      ]),
      allowedVerticals: ["general", "docs"]
    )

    XCTAssertEqual(plan.count, 1)
    XCTAssertEqual(plan[0].query, "Swift concurrency updates")
    XCTAssertEqual(plan[0].purpose, "Verify current behavior")
    XCTAssertEqual(plan[0].verticals, ["docs"])
    XCTAssertEqual(plan[0].categories, ["apple platforms"])
    XCTAssertEqual(plan[0].engines, ["engine-one"])
  }

  func testResearchResultsAreMergedFairlyAcrossQueries() {
    let merged = AgentIOSWebResearchPlanCodec.roundRobinResults([
      [
        ["url": .string("https://first.test/1")],
        ["url": .string("https://first.test/2")]
      ],
      [
        ["url": .string("https://second.test/1")],
        ["url": .string("https://first.test/1")],
        ["url": .string("https://second.test/2")]
      ]
    ])

    XCTAssertEqual(
      merged.compactMap { $0["url"]?.stringValue },
      [
        "https://first.test/1",
        "https://second.test/1",
        "https://first.test/2",
        "https://second.test/2"
      ]
    )
  }

  func testResearchEvidencePackCarriesCoverageAndUnresolvedQueries() throws {
    let attached = AgentIOSWebEvidencePack.attach(
      to: [
        "operation": .string("research"),
        "status": .string("partial"),
        "query": .string("compare options"),
        "research": .object([
          "query_plan": .array([
            .object(["query": .string("option A"), "purpose": .string("coverage A")])
          ]),
          "coverage": .array([
            .object([
              "query": .string("option A"),
              "status": .string("unresolved"),
              "candidate_count": .int(0)
            ])
          ]),
          "unresolved_queries": .array([.string("option A")])
        ])
      ],
      generatedAtMillis: 123
    )

    let context = try XCTUnwrap(
      attached["evidence_pack"]?.objectValue?["research_context"]?.objectValue
    )
    XCTAssertEqual(context["unresolved_queries"]?.arrayValue, [.string("option A")])
    XCTAssertEqual(
      context["coverage"]?.arrayValue?.first?.objectValue?["status"],
      .string("unresolved")
    )
  }
}
