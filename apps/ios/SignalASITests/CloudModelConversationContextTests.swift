import XCTest
@testable import SignalASI

final class CloudModelConversationContextTests: XCTestCase {
  func testPrepareLeavesSmallConversationIntact() {
    let prepared = CloudModelConversationContext.prepare(
      model: model(),
      apiKey: "sk-live",
      turns: [
        ChatMessage(contactId: "contact", content: "hello", isMine: true),
        ChatMessage(contactId: "contact", content: "answer", isMine: false)
      ],
      systemPrompt: "system",
      contextWindowTokens: 32_768
    )

    XCTAssertFalse(prepared.compacted)
    XCTAssertEqual(prepared.systemPrompt, "system")
    XCTAssertEqual(prepared.turns.map(\.content), ["hello", "answer"])
  }

  func testPrepareCompactsLargeConversationAndPreservesLatestUserGoal() {
    let turns = (0..<40).map { index in
      ChatMessage(
        contactId: "contact",
        content: String(repeating: "message \(index) ", count: 80),
        isMine: index.isMultiple(of: 2),
        conversationId: "conversation"
      )
    }

    let prepared = CloudModelConversationContext.prepare(
      model: model(),
      apiKey: "sk-live",
      turns: turns,
      systemPrompt: "system",
      contextWindowTokens: 4_096
    )

    XCTAssertTrue(prepared.compacted)
    XCTAssertLessThan(prepared.compactedEstimatedTokens, prepared.originalEstimatedTokens)
    XCTAssertTrue(prepared.systemPrompt.contains("system"))
    XCTAssertEqual(prepared.turns.last?.content, turns.last?.content)
    XCTAssertEqual(prepared.turns.last?.conversationId, "conversation")
  }

  private func model() -> CloudModelConfig {
    CloudModelConfig(
      id: "model",
      displayName: "Model",
      provider: "OpenAI",
      modelId: "model-id",
      endpoint: "https://api.example.test/v1/chat/completions",
      apiStyle: .openAICompatible,
      keychainAccount: "model",
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }
}
