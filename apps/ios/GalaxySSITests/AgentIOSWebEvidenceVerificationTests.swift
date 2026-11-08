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

  func testMissingCitationProducesBoundedRepairPromptWithVerifiedID() {
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
    XCTAssertTrue(prompt.contains("citation_id"))
    XCTAssertFalse(prompt.contains("https://example.test/report"))
    XCTAssertLessThanOrEqual(prompt.count, 8_000)
  }

  func testExactIDsResolveToAngleLinksWithoutChangingProtectedMarkdown() throws {
    let pack = AgentIOSWebEvidencePack.build(query: "report", status: "completed",
      documents: [["url": .string("https://example.test/report(part)?page=1"), "content": .string("Evidence")]],
      results: [], receipts: [], generatedAtMillis: 1)
    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)
    let url = item.string("url")
    let marker = "[[cite:\(item.string("citation_id"))]]"
    let evidence = [("web_research", AgentMcpJSONCodec.stringify(["evidence_pack": .object(pack)]))]
    let protected = [
      "``\(marker)``",
      "```text\n\(marker)\n```",
      "> ~~~text\n> \(marker)\n> ~~~",
      "    \(marker)",
      "<code data-value='a>b'>\(marker)</CODE>",
      "[Label \(marker)](<\(url)>)",
      "![Image \(marker)](<\(url)>)",
      "[Reference \(marker)][report]",
      "\\\(marker)"
    ].joined(separator: "\n\n")
    let draft = "A claim \(marker).\n\n\(protected)"
    let resolved = AgentIOSWebEvidenceVerification.resolveCitations(draft, encodedToolResults: evidence)
    XCTAssertEqual(resolved.text, "A claim [1](<\(url)>).\n\n\(protected)")
    XCTAssertTrue(resolved.unresolved.isEmpty)
    XCTAssertTrue(AgentIOSWebEvidenceVerification.validateAnswer(draft, encodedToolResults: evidence).valid)
    let preview = CloudCitationPreview(evidence: evidence)
    XCTAssertEqual(preview.append("Claim \(marker).\n\n"), "Claim [1](<\(url)>).\n\n")
    XCTAssertNil(CloudCitationPreview(evidence: evidence).append("Claim [[cite:missing]].\n\n"))
    let codeOnly = "```\n[Fake](<\(url)>)\n```"
    XCTAssertEqual(AgentIOSWebEvidenceVerification.validateAnswer(codeOnly, encodedToolResults: evidence).status,
      "missing_citations")
  }

  func testTamperedAndUnknownIDsFailValidationAndLogsDoNotExposeURLs() throws {
    let pack = makePack()
    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)
    let marker = "[[cite:\(item.string("citation_id"))]]"
    let evidence = [("web_fetch", AgentMcpJSONCodec.stringify(["evidence_pack": .object(pack)]))]
    let draft = "Claim \(marker). Other [[cite:unknown]]. [Foreign](<https://bad.test/p(a)?token=private>)."
    let result = AgentIOSWebEvidenceVerification.validateAnswer(draft, encodedToolResults: evidence)
    XCTAssertEqual(result.status, "unresolved_citations")
    XCTAssertTrue(result.invalidCitationURLs.contains("cite:unknown"))
    let diagnostic = AgentIOSWebEvidenceVerification.mismatchReferenceHashes(result)
    XCTAssertFalse(diagnostic.contains("private"))
    XCTAssertEqual(diagnostic.split(separator: ",").map(\.count), [12, 12])
    var tampered = pack
    var invalid = item
    invalid["url"] = .string("https://foreign.test/report")
    tampered["items"] = .array([.object(invalid)])
    XCTAssertFalse(AgentIOSWebEvidenceVerification.validateAnswer("Claim \(marker).", packs: [tampered]).valid)
    XCTAssertFalse(AgentIOSWebEvidenceVerification.validateAnswer("Claim \(marker).", packs: []).valid)
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
