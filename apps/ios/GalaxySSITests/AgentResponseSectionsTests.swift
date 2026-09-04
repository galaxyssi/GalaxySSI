import XCTest
@testable import GalaxySSI

final class AgentResponseSectionsTests: XCTestCase {
  func testKeepsShortOrdinaryRepliesUnsectioned() {
    let layout = AgentResponseSectionOrganizer.organize([
      block("answer", .text, "Done.")
    ])

    XCTAssertFalse(layout.collapsible)
    XCTAssertEqual(layout.sections.count, 1)
    XCTAssertEqual(layout.sections.first?.kind, .finalAnswer)
  }

  func testGroupsExplicitSectionsAndExpandsOnlyTheFinalAnswerByDefault() {
    let layout = AgentResponseSectionOrganizer.organize([
      block("plan", .text, "Inspect and verify.", section: "plan"),
      block("tool", .tool, "Read project state."),
      block("final", .text, "The project is running.", section: "final"),
      block("source", .citation, "status.json")
    ])

    XCTAssertTrue(layout.collapsible)
    XCTAssertEqual(layout.sections.map { $0.kind }, [
      .plan,
      .executionLog,
      .finalAnswer,
      .evidence
    ])
    XCTAssertEqual(layout.sections.map { $0.expandedByDefault }, [
      false,
      false,
      true,
      false
    ])
  }

  func testRecognizesSectionHeadingsWithoutRenderingDuplicateHeadingBlocks() {
    let layout = AgentResponseSectionOrganizer.organize([
      block("heading-plan", .heading, "Plan"),
      block("plan-body", .list, "1. Inspect"),
      block("heading-result", .heading, "Final answer"),
      block("result-body", .text, "Verified.")
    ])

    XCTAssertTrue(layout.collapsible)
    XCTAssertEqual(layout.sections.first?.blocks.map { $0.id }, ["plan-body"])
    XCTAssertEqual(layout.sections.dropFirst().first?.blocks.map { $0.id }, ["result-body"])
  }

  func testKeepsDeliveredArtifactsInTheFinalAnswerUnlessMarkedAsEvidence() {
    let layout = AgentResponseSectionOrganizer.organize([
      block("image", .image, "result.png"),
      block("evidence", .image, "source.png", evidence: true)
    ])

    XCTAssertEqual(
      layout.sections.first { $0.kind == .finalAnswer }?.blocks.map { $0.id },
      ["image"]
    )
    XCTAssertEqual(
      layout.sections.first { $0.kind == .evidence }?.blocks.map { $0.id },
      ["evidence"]
    )
  }

  func testMakesLongPlainRepliesCollapsible() {
    let layout = AgentResponseSectionOrganizer.organize([
      block("long", .text, String(repeating: "x", count: 1_300))
    ])

    XCTAssertTrue(layout.collapsible)
    XCTAssertEqual(layout.sections.count, 1)
    XCTAssertTrue(layout.sections.first?.expandedByDefault == true)
  }

  func testKeepsInteractiveApprovalBlocksInTheExpandedFinalSection() {
    let layout = AgentResponseSectionOrganizer.organize([
      block("heading-plan", .heading, "Plan"),
      block("plan", .text, "Prepare the change."),
      block("approval", .approval, "Approve the protected action.")
    ])

    let finalSection = layout.sections.first { $0.kind == .finalAnswer }
    XCTAssertEqual(finalSection?.blocks.map { $0.id }, ["approval"])
    XCTAssertTrue(finalSection?.expandedByDefault == true)
  }

  func testMetadataSectionAliasesAreParsed() {
    let layout = AgentResponseSectionOrganizer.organize([
      block("source", .text, "trace", metadata: ["response_section": "sources"]),
      block("summary", .text, "ok", metadata: ["role": "answer"])
    ])

    XCTAssertTrue(layout.collapsible)
    XCTAssertEqual(layout.sections.map { $0.kind }, [.finalAnswer, .evidence])
    XCTAssertEqual(
      layout.sections.first { $0.kind == .evidence }?.blocks.map { $0.id },
      ["source"]
    )
    XCTAssertEqual(
      layout.sections.first { $0.kind == .finalAnswer }?.blocks.map { $0.id },
      ["summary"]
    )
  }

  private func block(
    _ id: String,
    _ type: AgentRichBlockType,
    _ text: String,
    section: String = "",
    evidence: Bool = false,
    metadata: [String: String] = [:]
  ) -> AgentRichBlock {
    var mergedMetadata = metadata
    if !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      mergedMetadata["section"] = section
    }
    if evidence {
      mergedMetadata["evidence"] = "true"
    }
    return AgentRichBlock(
      id: id,
      type: type,
      text: text,
      metadata: mergedMetadata
    )
  }
}
