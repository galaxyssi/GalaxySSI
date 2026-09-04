import XCTest
@testable import GalaxySSI

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

  func testContextOverflowRetryShrinksWindowsUntilSuccess() async throws {
    var attempts: [(window: Int, attempt: Int)] = []
    let result = try await CloudModelClient().withContextOverflowRetry(model: model(), apiKey: "sk-live") { window, attempt in
      attempts.append((window: window, attempt: attempt))
      if attempt < 2 {
        throw CloudHTTPFailure(statusCode: 400, responseBody: #"{"code":"context_length_exceeded"}"#)
      }
      return "ok"
    }

    XCTAssertEqual(result, "ok")
    XCTAssertEqual(attempts.map(\.attempt), [0, 1, 2])
    XCTAssertEqual(attempts.map(\.window), [128_000, 64_000, 32_000])
  }

  func testContextOverflowRetryDoesNotRetryNonOverflowHTTPFailure() async {
    var attempts = 0
    do {
      _ = try await CloudModelClient().withContextOverflowRetry(model: model(), apiKey: "sk-live") { _, _ in
        attempts += 1
        throw CloudHTTPFailure(statusCode: 401, responseBody: "bad key")
      }
      XCTFail("Expected non-overflow HTTP failure.")
    } catch let error as GalaxySSIError {
      XCTAssertEqual(error.errorDescription, "Invalid GalaxySSI payload: Cloud request failed with 401: bad key")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(attempts, 1)
  }

  private func model() -> CloudModelConfig {
    CloudModelConfig(
      id: "model",
      displayName: "Model",
      provider: "OpenAI",
      modelId: "gpt-5",
      endpoint: "https://api.example.test/v1/chat/completions",
      apiStyle: .openAICompatible,
      keychainAccount: "model",
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }
}
