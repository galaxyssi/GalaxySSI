import XCTest
@testable import GalaxySSI

final class AgentDirectVisionPolicyTests: XCTestCase {
  func testImageUsesNativeVisionAndRequiresEvidenceReview() {
    let instruction = AgentDirectVisionPolicy.instructionForMimeTypes(["image/jpeg"])

    XCTAssertTrue(instruction.contains("native visual model input"))
    XCTAssertTrue(instruction.contains("inspect the image twice"))
    XCTAssertTrue(instruction.contains("visible shape, logos, and readable text"))
    XCTAssertTrue(instruction.contains("unrelated prior images and memories"))
    XCTAssertFalse(instruction.localizedCaseInsensitiveContains("OCR"))
  }

  func testNonImageAttachmentDoesNotAddVisionInstructions() {
    XCTAssertTrue(AgentDirectVisionPolicy.instructionForMimeTypes(["application/pdf"]).isEmpty)
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
