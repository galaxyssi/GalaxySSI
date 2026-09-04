import XCTest
@testable import GalaxySSI

final class CloudModelStreamProviderAdaptersTests: XCTestCase {
  func testOpenAIChatCompletionDeltaParsesTextToolUsageAndFinishReason() {
    let adapter = ModelStreamProviderAdapters.create(provider: .openAICompatible)
    let frame = adapter.parse(
      data: """
      {
        "choices": [{
          "delta": {
            "content": "hello",
            "tool_calls": [{
              "id": "call-1",
              "index": 0,
              "function": {"name": "search", "arguments": "{\\"q\\":\\"sig\\"}"}
            }]
          },
          "finish_reason": "tool_calls"
        }],
        "usage": {
          "prompt_tokens": 7,
          "completion_tokens": 3,
          "prompt_tokens_details": {"cached_tokens": 2}
        },
        "sequence": 9
      }
      """,
      eventName: nil
    )

    XCTAssertEqual(frame.textDeltas, ["hello"])
    XCTAssertEqual(
      frame.toolDeltas,
      [ToolCallPayload(callId: "call-1", index: 0, nameDelta: "search", argumentsDelta: #"{"q":"sig"}"#)]
    )
    XCTAssertEqual(frame.usage, ModelUsage(inputTokens: 7, outputTokens: 3, cachedInputTokens: 2))
    XCTAssertEqual(frame.finishReason, "tool_calls")
    XCTAssertEqual(frame.providerSequence, 9)
  }

  func testOpenAIResponsesApiDeltaAndDoneFrames() {
    let adapter = ModelStreamProviderAdapters.create(provider: .openAICompatible)
    let text = adapter.parse(
      data: #"{"type":"response.output_text.delta","delta":"hi","seq":2}"#,
      eventName: nil
    )
    let tool = adapter.parse(
      data: #"{"type":"response.function_call_arguments.delta","item_id":"item-1","output_index":1,"name":"lookup","delta":"{\"id\":1}"}"#,
      eventName: nil
    )
    let done = adapter.parse(data: "[DONE]", eventName: nil)

    XCTAssertEqual(text.textDeltas, ["hi"])
    XCTAssertEqual(text.providerSequence, 2)
    XCTAssertEqual(
      tool.toolDeltas,
      [ToolCallPayload(callId: "item-1", index: 1, nameDelta: "lookup", argumentsDelta: #"{"id":1}"#)]
    )
    XCTAssertTrue(done.terminal)
  }

  func testAnthropicToolUseDeltasPreserveStartedToolBlock() {
    let adapter = ModelStreamProviderAdapters.create(provider: .anthropic)
    let start = adapter.parse(
      data: #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"search","input":{"q":"sig"}}}"#,
      eventName: nil
    )
    let delta = adapter.parse(
      data: #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"nal"}}"#,
      eventName: nil
    )
    let stop = adapter.parse(data: #"{"type":"message_stop"}"#, eventName: nil)

    XCTAssertEqual(
      start.toolDeltas,
      [ToolCallPayload(callId: "toolu_1", index: 0, nameDelta: "search", argumentsDelta: #"{"q":"sig"}"#)]
    )
    XCTAssertEqual(
      delta.toolDeltas,
      [ToolCallPayload(callId: "toolu_1", index: 0, nameDelta: "search", argumentsDelta: "nal")]
    )
    XCTAssertTrue(stop.terminal)
  }

  func testGeminiParsesTextFunctionCallUsageAndTerminalFinish() {
    let adapter = ModelStreamProviderAdapters.create(provider: .gemini)
    let frame = adapter.parse(
      data: """
      {
        "candidates": [{
          "finishReason": "STOP",
          "content": {
            "parts": [
              {"text": "answer"},
              {"functionCall": {"name": "lookup", "args": {"id": 7}}}
            ]
          }
        }],
        "usageMetadata": {
          "promptTokenCount": 11,
          "candidatesTokenCount": 5,
          "cachedContentTokenCount": 4
        }
      }
      """,
      eventName: nil
    )

    XCTAssertEqual(frame.textDeltas, ["answer"])
    XCTAssertEqual(
      frame.toolDeltas,
      [ToolCallPayload(callId: "gemini-1", index: 1, nameDelta: "lookup", argumentsDelta: #"{"id":7}"#)]
    )
    XCTAssertEqual(frame.usage, ModelUsage(inputTokens: 11, outputTokens: 5, cachedInputTokens: 4))
    XCTAssertEqual(frame.finishReason, "STOP")
    XCTAssertTrue(frame.terminal)
  }

  func testProviderErrorIsNormalized() {
    let adapter = ModelStreamProviderAdapters.create(provider: .openAICompatible)
    let frame = adapter.parse(
      data: #"{"error":{"code":"rate_limit","message":"slow down"}}"#,
      eventName: nil
    )

    XCTAssertEqual(
      frame.error,
      ModelStreamError(code: "rate_limit", message: "slow down")
    )
  }
}
