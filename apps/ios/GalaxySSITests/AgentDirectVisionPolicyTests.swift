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

  func testCodexSparkImageUsesLunaWithHighReasoning() {
    let invocation = AgentDirectVisionPolicy.invocation(
      modelId: "gpt-5.3-codex-spark",
      reasoningEffort: .xhigh,
      mimeTypes: ["image/png"]
    )

    XCTAssertEqual(invocation.modelId, "gpt-5.6-luna")
    XCTAssertEqual(invocation.reasoningEffort, .high)
  }

  func testTextTurnKeepsRequestedInvocation() {
    let invocation = AgentDirectVisionPolicy.invocation(
      modelId: "gpt-5.3-codex-spark",
      reasoningEffort: .xhigh,
      mimeTypes: []
    )

    XCTAssertEqual(invocation.modelId, "gpt-5.3-codex-spark")
    XCTAssertEqual(invocation.reasoningEffort, .xhigh)
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
