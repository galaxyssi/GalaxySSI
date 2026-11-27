import XCTest
@testable import GalaxySSI

final class AgentConversationGoalInferenceTests: XCTestCase {
  private func request(_ provider: ModelStreamProvider, _ body: [String: Any], endpoint: String = "https://example.invalid/v1/chat/completions") throws -> ModelStreamRequest {
    .init(requestId: "synthetic-goal", provider: provider, endpoint: endpoint, headers: [:],
      bodyJson: String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self))
  }
  private func object(_ request: ModelStreamRequest) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.bodyJson.utf8)) as? [String: Any])
  }
  func testOpenAITextRequestHasOneUserNoToolsAndBoundedCompletion() throws {
    let input = try request(.openAICompatible, ["messages": [["role": "system", "content": "inherited system"],
      ["role": "user", "content": "synthetic goal"]], "tools": [["name": "send_message"]], "tool_choice": "auto"],
      endpoint: "https://api.openai.com/v1/chat/completions")
    let result = try AgentConversationGoalInference.isolatedRequest(input, system: "fixed goal instructions")
    let body = try object(result)
    XCTAssertNil(body["tools"]); XCTAssertNil(body["tool_choice"]); XCTAssertNil(body["max_tokens"])
    XCTAssertEqual(body["max_completion_tokens"] as? Int, 3_000)
    XCTAssertEqual((body["messages"] as? [[String: String]])?.first?["content"], "fixed goal instructions")
    XCTAssertEqual(result.readTimeoutMs, 120_000)
  }
  func testUnexpectedChatHistoryIsRejected() throws {
    let input = try request(.openAICompatible, ["messages": [["role": "system"], ["role": "user"], ["role": "assistant"]]])
    XCTAssertThrowsError(try AgentConversationGoalInference.isolatedRequest(input, system: "fixed"))
  }
  func testAnthropicAndGeminiDoNotAdvertiseTools() throws {
    let anthropic = try AgentConversationGoalInference.isolatedRequest(request(.anthropic, ["messages": [["role": "user", "content": "goal"]],
      "tools": [["name": "browser"]], "system": "inherited"]), system: "fixed")
    XCTAssertNil(try object(anthropic)["tools"])
    XCTAssertEqual(try object(anthropic)["max_tokens"] as? Int, 3_000)
    let gemini = try AgentConversationGoalInference.isolatedRequest(request(.gemini, ["contents": [["role": "user"]],
      "tools": [["functionDeclarations": []]], "toolConfig": [:]]), system: "fixed")
    let body = try object(gemini)
    XCTAssertNil(body["tools"]); XCTAssertNil(body["toolConfig"])
    XCTAssertEqual((body["generationConfig"] as? [String: Int])?["maxOutputTokens"], 3_000)
  }
  func testGoalHandoffContainsOnlyExplicitScope() throws {
    let goal = try AgentConversationGoal(conversation: "synthetic-chat", objective: "Write fiction.",
      route: .init(kind: .local, target: "local-llm", model: "synthetic", endpointSHA: "", host: "")).claim()
    let prompt = try AgentConversationGoalInference.prompt(goal)
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])
    XCTAssertEqual(Set(body.keys), ["objective", "checkpoints", "pending", "clarification", "remaining_rounds"])
    XCTAssertEqual(body["objective"] as? String, "Write fiction.")
    XCTAssertEqual(body["remaining_rounds"] as? Int, 5)
    XCTAssertEqual(body["checkpoints"] as? [String], [])
  }
  func testFinalReviewIsAnExplicitSeparateInstruction() {
    XCTAssertFalse(AgentConversationGoalInference.system(review: false, language: "en").contains("FINAL REVIEW"))
    XCTAssertTrue(AgentConversationGoalInference.system(review: true, language: "en").contains("FINAL REVIEW"))
    XCTAssertTrue(AgentConversationGoalInference.system(review: true, language: "en").contains("unsupported external claims do not pass"))
  }
}
