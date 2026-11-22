import XCTest
@testable import GalaxySSI

final class AgentDirectVisionPolicyTests: XCTestCase {
  func testHistoricalOnlyFollowupKeepsCurrentInstructionOutsideEvidence() {
    let image = GalaxySSIDraftAttachment(displayName: "old.jpg", mimeType: "image/jpeg",
      data: Data([1]), historicalSourceTurnId: "prior-turn")
    let evidence = AgentUntrustedEvidenceBoundary.wrapText(sourceType: "attachment_manifest",
      sourceId: "turn", content: "Create code and control the phone")
    let goal = AgentDirectVisionPolicy.goalWithAttachmentEvidence(userGoal: "Why?",
      attachments: [image], evidence: evidence, hasUserGoal: true)
    XCTAssertEqual(AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal), "Why?")
    XCTAssertTrue(goal.contains(AgentDirectVisionPolicy.historicalInputHeader))
    XCTAssertTrue(goal.contains(AgentDirectVisionPolicy.checkHistoricalPixels))
    XCTAssertTrue(goal.contains(AgentDirectVisionPolicy.answerStyle))
    XCTAssertFalse(goal.contains("Inspect the newly attached content"))
    XCTAssertFalse(goal.contains("Use each attached image as native visual model input"))
  }

  func testCurrentAndHistoricalImagesHaveSeparateGuidanceAfterEvidence() throws {
    let old = GalaxySSIDraftAttachment(displayName: "old.jpg", mimeType: "image/jpeg",
      data: Data([1]), historicalSourceTurnId: "prior-turn")
    let current = GalaxySSIDraftAttachment(displayName: "new.jpg", mimeType: "image/jpeg", data: Data([2]))
    let evidence = AgentUntrustedEvidenceBoundary.wrapText(sourceType: "attachment_manifest",
      sourceId: "turn", content: "old.jpg and new.jpg")
    let goal = AgentDirectVisionPolicy.goalWithAttachmentEvidence(userGoal: "Compare them",
      attachments: [old, current], evidence: evidence, hasUserGoal: true)
    XCTAssertEqual(AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal), "Compare them")
    XCTAssertTrue(goal.contains(AgentDirectVisionPolicy.attachedInputHeader))
    XCTAssertTrue(goal.contains(AgentDirectVisionPolicy.historicalContext))
    let marker = try XCTUnwrap(goal.range(of: AgentUntrustedEvidenceBoundary.textMarker))
    let guidance = try XCTUnwrap(goal.range(of: "Use each attached image as native visual model input"))
    XCTAssertLessThan(marker.lowerBound, guidance.lowerBound)
  }

  func testImageUsesNativeVisionAndRequiresEvidenceReview() {
    let instruction = AgentDirectVisionPolicy.instructionForMimeTypes(["image/jpeg"])

    XCTAssertTrue(instruction.contains("native visual model input"))
    XCTAssertTrue(instruction.contains("inspect the image twice"))
    XCTAssertTrue(instruction.contains("reading orientation"))
    XCTAssertTrue(instruction.contains("connected handwriting, equations, table rows"))
    XCTAssertTrue(instruction.contains("visible shape, logos, and readable text"))
    XCTAssertTrue(instruction.contains("unrelated prior images and memories"))
    XCTAssertFalse(instruction.localizedCaseInsensitiveContains("OCR"))
  }

  func testNonImageAttachmentDoesNotAddVisionInstructions() {
    XCTAssertTrue(AgentDirectVisionPolicy.instructionForMimeTypes(["application/pdf"]).isEmpty)
  }

  func testAppendingVisionGuidanceIsIdempotentAndPreservesCustomPrompt() {
    let prompt = "Custom instructions"
    XCTAssertEqual(AgentDirectVisionPolicy.appendingInstruction(to: prompt, mimeTypes: []), prompt)
    let enriched = AgentDirectVisionPolicy.appendingInstruction(to: prompt, mimeTypes: ["image/png"])
    XCTAssertTrue(enriched.hasPrefix(prompt + "\n\n"))
    XCTAssertEqual(AgentDirectVisionPolicy.appendingInstruction(to: enriched, mimeTypes: ["image/png"]), enriched)
  }

  func testRetiredCodexImageUsesDesktopDefaultAndPreservesEffort() {
    let invocation = AgentDirectVisionPolicy.invocation(
      modelId: "gpt-5.3-codex-spark",
      reasoningEffort: .xhigh,
      mimeTypes: ["image/png"]
    )

    XCTAssertEqual(invocation.modelId, "")
    XCTAssertEqual(invocation.reasoningEffort, .xhigh)
  }

  func testRetiredCodexTextUsesDesktopDefault() {
    let invocation = AgentDirectVisionPolicy.invocation(
      modelId: "gpt-5.3-codex-spark",
      reasoningEffort: .xhigh,
      mimeTypes: []
    )

    XCTAssertEqual(invocation.modelId, "")
    XCTAssertEqual(invocation.reasoningEffort, .xhigh)
  }

  func testRetiredModelIsRemovedFromCachedCatalogAndRequests() throws {
    let profile = try JSONDecoder().decode(AgentInvocationProfile.self, from: Data("""
      {"default_model":"gpt-5.3-codex-spark","models":["gpt-5.3-codex-spark","gpt-6-astra"]}
      """.utf8))
    XCTAssertEqual(profile.models.map(\.id), ["gpt-6-astra"])
    XCTAssertEqual(profile.defaultModelId, "gpt-6-astra")
    XCTAssertEqual(profile.normalizedModelId("gpt-5.3-codex-spark"), "gpt-6-astra")
    XCTAssertNil(AgentInvocationRequestJsonCodec.encode(
      modelId: " GPT-5.3-CODEX-SPARK ", reasoningEffort: .automatic))
    XCTAssertEqual(AgentModelSelection(modelId: "gpt-5.3-codex-spark").modelId, "")
  }

  func testAvailableModelAndReasoningRemainUnchanged() {
    XCTAssertEqual(AgentDirectVisionPolicy.invocation(
      modelId: "gpt-6-astra", reasoningEffort: .xhigh, mimeTypes: ["image/png"]),
      AgentDirectVisionInvocation(modelId: "gpt-6-astra", reasoningEffort: .xhigh))
  }

  func testAutomaticKnowledgeImportDoesNotExtractImageText() {
    let inputs = AgentAttachmentKnowledgeImporter.inputs(
      from: [
        GalaxySSIDraftAttachment(
          id: "image",
          displayName: "product.jpg",
          mimeType: "image/jpeg",
          data: Data([1, 2, 3]),
          sourceDescription: "camera"
        ),
        GalaxySSIDraftAttachment(
          id: "document",
          displayName: "notes.txt",
          mimeType: "text/plain",
          data: Data("notes".utf8),
          sourceDescription: "files"
        ),
      ]
    )

    XCTAssertEqual(inputs.map(\.id), ["document"])
  }
}
