import XCTest
@testable import GalaxySSI

final class AgentIOSWebEvidenceVerificationTests: XCTestCase {
  func testBuiltPackHasVerifiedManifestAndExpandedSynthesisContract() throws {
    let pack = makePack()
    let verification = try XCTUnwrap(pack["verification"]?.objectValue)
    let contract = try XCTUnwrap(pack["synthesis_contract"]?.objectValue)

    XCTAssertEqual(verification["status"], .string("verified"))
    XCTAssertEqual(verification["valid_item_count"], .int(1))
    XCTAssertEqual(contract["never_invent_citations"], .bool(true))
    XCTAssertEqual(contract["compare_independent_retrieved_bodies"], .bool(true))
  }

  func testAnswerMustUseMarkdownLinkFromEvidencePack() throws {
    let pack = makePack()
    let encoded = AgentMcpJSONCodec.stringify(["evidence_pack": .object(pack)])
    let valid = AgentIOSWebEvidenceVerification.validateAnswer(
      "Supported claim [Source](https://example.test/report).",
      encodedToolResults: [("fetch", encoded)]
    )
    let foreign = AgentIOSWebEvidenceVerification.validateAnswer(
      "Unsupported [Source](https://other.test/report).",
      encodedToolResults: [("fetch", encoded)]
    )

    XCTAssertTrue(valid.valid)
    XCTAssertEqual(foreign.status, "foreign_citations")
    XCTAssertTrue(foreign.requiresRepair)
  }

  func testMissingCitationProducesBoundedRepairPromptWithExactURL() {
    let pack = makePack()
    let encoded = AgentMcpJSONCodec.stringify(["evidence_pack": .object(pack)])
    let validation = AgentIOSWebEvidenceVerification.validateAnswer(
      "A claim without a source.",
      encodedToolResults: [("fetch", encoded)]
    )
    let prompt = AgentIOSWebEvidenceVerification.repairPrompt(
      validation: validation,
      encodedToolResults: [("fetch", encoded)]
    )

    XCTAssertEqual(validation.status, "missing_citations")
    XCTAssertTrue(prompt.contains("https://example.test/report"))
    XCTAssertLessThanOrEqual(prompt.count, 8_000)
  }

  func testCrossDomainNumericMismatchIsMarkedForModelReview() throws {
    let pack = AgentIOSWebEvidencePack.build(
      query: "revenue",
      status: "completed",
      documents: [
        [
          "url": .string("https://one.test/report"),
          "content": .string("Reported revenue was 10 USD during the measured quarter.")
        ],
        [
          "url": .string("https://two.test/report"),
          "content": .string("Reported revenue was 12 USD during the measured quarter.")
        ]
      ],
      results: [],
      receipts: [],
      generatedAtMillis: 1
    )
    let review = try XCTUnwrap(pack["conflict_review"]?.objectValue)

    XCTAssertEqual(review["status"], .string("potential_conflict"))
    XCTAssertEqual(review["review_required"], .bool(true))
    XCTAssertEqual(review["potential_conflicts"]?.arrayValue?.count, 1)
  }

  private func makePack() -> AgentMcpJSONObject {
    AgentIOSWebEvidencePack.build(
      query: "report",
      status: "completed",
      documents: [[
        "url": .string("https://www.example.test/report?utm_source=search"),
        "title": .string("Report"),
        "content": .string("Complete retrieved evidence for the report.")
      ]],
      results: [],
      receipts: [],
      generatedAtMillis: 123
    )
  }
}
