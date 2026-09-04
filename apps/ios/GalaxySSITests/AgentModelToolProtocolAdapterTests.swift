import Foundation
import XCTest
@testable import GalaxySSI

final class AgentModelToolProtocolAdapterTests: XCTestCase {
  func testOpenAICompatibleEncodesCatalogConversationAndDecodesParallelCalls() throws {
    let adapter = OpenAiCompatibleAgentModelToolProtocolAdapter()
    let catalog = try testCatalog()

    let tools = try adapter.encodeToolCatalog(catalog)
    XCTAssertEqual(tools.count, 2)
    let echoTool = try tools.requiredObject(0)
    XCTAssertEqual(try echoTool.requiredString("type"), "function")
    let echoFunction = try echoTool.requiredObject("function")
    XCTAssertEqual(try echoFunction.requiredString("name"), Self.echoToolId)
    XCTAssertEqual(try echoFunction.requiredObject("parameters").requiredString("type"), "object")

    let response = try adapter.decodeResponse(
      #"""
      {
        "id": "chatcmpl-1",
        "model": "test-model",
        "choices": [{
          "message": {
            "role": "assistant",
            "content": [
              {"type": "text", "text": "Checking both tools."},
              {"type": "text", "text": "Please wait."}
            ],
            "tool_calls": [
              {
                "id": "call-openai-1",
                "type": "function",
                "function": {"name": "\#(Self.echoToolId)", "arguments": "{\"value\":\"hello\"}"}
              },
              {
                "id": "call-openai-2",
                "type": "function",
                "function": {"name": "\#(Self.sumToolId)", "arguments": "{\"left\":2,\"right\":3}"}
              }
            ]
          },
          "finish_reason": "tool_calls"
        }],
        "usage": {"prompt_tokens": 13, "completion_tokens": 7, "total_tokens": 20}
      }
      """#,
      catalog: catalog
    )

    XCTAssertEqual(response.assistantText, "Checking both tools.\nPlease wait.")
    XCTAssertEqual(response.toolCalls.map(\.callId), ["call-openai-1", "call-openai-2"])
    XCTAssertEqual(response.toolCalls.map(\.toolId), [Self.echoToolId, Self.sumToolId])
    XCTAssertEqual(response.toolCalls[0].arguments["value"], .string("hello"))
    XCTAssertEqual(response.toolCalls[1].arguments["right"], .int(3))
    XCTAssertEqual(response.toolCalls[0].toolVersion, "1.0.0")
    XCTAssertEqual(response.usage.inputTokens, 13)
    XCTAssertEqual(response.usage.outputTokens, 7)
    XCTAssertEqual(response.providerMetadata["finish_reason"], .string("tool_calls"))
    XCTAssertEqual(response.providerMetadata["response_id"], .string("chatcmpl-1"))

    let conversation = try adapter.encodeConversation([
      .system("Use native tools."),
      .user("Echo and add."),
      .assistant(response.assistantText, toolCalls: response.toolCalls),
      toolResult("call-openai-1", Self.echoToolId, output: ["echo": .string("hello")])
    ])
    let messages = try conversation.requiredArray("messages")
    let assistant = try messages.requiredObject(2)
    let calls = try assistant.requiredArray("tool_calls")
    XCTAssertEqual(try calls.requiredObject(1).requiredString("id"), "call-openai-2")
    XCTAssertEqual(try messages.requiredObject(3).requiredString("tool_call_id"), "call-openai-1")
  }

  func testAnthropicEncodesBlocksAndDecodesUsageAndStopReason() throws {
    let adapter = AnthropicAgentModelToolProtocolAdapter()
    let catalog = try testCatalog()

    let tools = try adapter.encodeToolCatalog(catalog)
    XCTAssertEqual(try tools.requiredObject(0).requiredString("name"), Self.echoToolId)
    XCTAssertEqual(try tools.requiredObject(0).requiredObject("input_schema").requiredString("type"), "object")

    let response = try adapter.decodeResponse(
      #"""
      {
        "id": "msg-1",
        "model": "claude-test",
        "content": [
          {"type": "text", "text": "I will check."},
          {"type": "tool_use", "id": "call-anthropic-1", "name": "\#(Self.echoToolId)", "input": {"value": "hi"}},
          {"type": "tool_use", "id": "call-anthropic-2", "name": "\#(Self.sumToolId)", "input": {"left": 4, "right": 5}},
          {"type": "text", "text": "Both are independent."}
        ],
        "stop_reason": "tool_use",
        "usage": {
          "input_tokens": 10,
          "cache_creation_input_tokens": 2,
          "cache_read_input_tokens": 3,
          "output_tokens": 8
        }
      }
      """#,
      catalog: catalog
    )

    XCTAssertEqual(response.assistantText, "I will check.\nBoth are independent.")
    XCTAssertEqual(response.toolCalls.map(\.callId), ["call-anthropic-1", "call-anthropic-2"])
    XCTAssertEqual(response.usage.inputTokens, 15)
    XCTAssertEqual(response.usage.outputTokens, 8)
    XCTAssertEqual(response.providerMetadata["finish_reason"], .string("tool_use"))
    XCTAssertEqual(response.providerMetadata["stop_reason"], .string("tool_use"))

    let conversation = try adapter.encodeConversation([
      .system("Use native tools."),
      .user("Run both."),
      .assistant(toolCalls: response.toolCalls),
      toolResult("call-anthropic-1", Self.echoToolId, output: ["echo": .string("hi")]),
      toolResult("call-anthropic-2", Self.sumToolId, status: "failed", output: ["reason": .string("offline")])
    ])
    XCTAssertEqual(conversation["system"], .string("Use native tools."))
    let messages = try conversation.requiredArray("messages")
    let assistantBlocks = try messages.requiredObject(1).requiredArray("content")
    XCTAssertEqual(try assistantBlocks.requiredObject(1).requiredString("id"), "call-anthropic-2")
    let resultBlocks = try messages.requiredObject(2).requiredArray("content")
    XCTAssertEqual(resultBlocks.count, 2)
    XCTAssertEqual(try resultBlocks.requiredObject(0).requiredString("tool_use_id"), "call-anthropic-1")
    XCTAssertEqual(try resultBlocks.requiredObject(0).requiredBool("is_error"), false)
    XCTAssertEqual(try resultBlocks.requiredObject(1).requiredBool("is_error"), true)
  }

  func testGeminiEncodesFunctionsAndPreservesParallelCallIds() throws {
    let adapter = GeminiAgentModelToolProtocolAdapter()
    let catalog = try testCatalog()

    let tools = try adapter.encodeToolCatalog(catalog)
    let declarations = try tools.requiredObject(0).requiredArray("functionDeclarations")
    XCTAssertEqual(declarations.count, 2)
    XCTAssertEqual(try declarations.requiredObject(0).requiredString("name"), Self.echoToolId)
    XCTAssertEqual(try declarations.requiredObject(0).requiredObject("response").requiredString("type"), "object")

    let response = try adapter.decodeResponse(
      #"""
      {
        "responseId": "gemini-response-1",
        "modelVersion": "gemini-test",
        "candidates": [{
          "content": {
            "role": "model",
            "parts": [
              {"text": "Calling two functions."},
              {"functionCall": {"id": "call-gemini-1", "name": "\#(Self.echoToolId)", "args": {"value": "hola"}}},
              {"functionCall": {"id": "call-gemini-2", "name": "\#(Self.sumToolId)", "args": {"left": 8, "right": 9}}},
              {"text": "Results will follow."}
            ]
          },
          "finishReason": "STOP"
        }],
        "usageMetadata": {
          "promptTokenCount": 21,
          "candidatesTokenCount": 9,
          "totalTokenCount": 30
        }
      }
      """#,
      catalog: catalog
    )

    XCTAssertEqual(response.assistantText, "Calling two functions.\nResults will follow.")
    XCTAssertEqual(response.toolCalls.map(\.callId), ["call-gemini-1", "call-gemini-2"])
    XCTAssertEqual(response.usage.inputTokens, 21)
    XCTAssertEqual(response.usage.outputTokens, 9)
    XCTAssertEqual(response.providerMetadata["finish_reason"], .string("STOP"))
    XCTAssertEqual(response.providerMetadata["response_id"], .string("gemini-response-1"))

    let conversation = try adapter.encodeConversation([
      .system("Use native tools."),
      .user("Run both."),
      .assistant(toolCalls: response.toolCalls),
      toolResult("call-gemini-1", Self.echoToolId, output: ["echo": .string("hola")]),
      toolResult("call-gemini-2", Self.sumToolId, output: ["sum": .int(17)])
    ])
    XCTAssertEqual(
      try conversation.requiredObject("system_instruction")
        .requiredArray("parts")
        .requiredObject(0)
        .requiredString("text"),
      "Use native tools."
    )
    let contents = try conversation.requiredArray("contents")
    let calls = try contents.requiredObject(1).requiredArray("parts")
    XCTAssertEqual(try calls.requiredObject(0).requiredObject("functionCall").requiredString("id"), "call-gemini-1")
    let results = try contents.requiredObject(2).requiredArray("parts")
    XCTAssertEqual(
      try results.requiredObject(1).requiredObject("functionResponse").requiredString("id"),
      "call-gemini-2"
    )
  }

  func testRejectsMalformedUnknownAndOversizedCalls() throws {
    let catalog = try testCatalog()

    expectProtocolError("malformed_tool_call") {
      _ = try OpenAiCompatibleAgentModelToolProtocolAdapter().decodeResponse(
        #"""
        {"choices":[{"message":{"tool_calls":[{
          "id":"bad-1","type":"function",
          "function":{"name":"\#(Self.echoToolId)","arguments":"not-json"}
        }]},"finish_reason":"tool_calls"}]}
        """#,
        catalog: catalog
      )
    }

    expectProtocolError("unknown_tool") {
      _ = try AnthropicAgentModelToolProtocolAdapter().decodeResponse(
        #"""
        {"content":[{
          "type":"tool_use","id":"unknown-1","name":"phone.test.unknown","input":{}
        }],"stop_reason":"tool_use"}
        """#,
        catalog: catalog
      )
    }

    let limits = AgentModelToolProtocolLimits(maxArgumentsCharacters: 32)
    expectProtocolError("oversized_tool_call") {
      _ = try GeminiAgentModelToolProtocolAdapter(limits: limits).decodeResponse(
        #"""
        {"candidates":[{"content":{"parts":[{"functionCall":{
          "id":"large-1","name":"\#(Self.echoToolId)","args":{"value":"\#(String(repeating: "x", count: 80))"}
        }}]},"finishReason":"STOP"}]}
        """#,
        catalog: catalog
      )
    }
  }

  func testEmitsBoundedToolResultsForEveryProvider() throws {
    let limits = AgentModelToolProtocolLimits(maxToolResultCharacters: 220)
    let result = toolResult(
      "bounded-call",
      Self.echoToolId,
      output: ["payload": .string(String(repeating: "x", count: 2_000))],
      message: String(repeating: "m", count: 1_000)
    )
    let assistant = AgentModelMessage.assistant(toolCalls: [
      AgentModelToolCall(callId: "bounded-call", toolId: Self.echoToolId, arguments: ["value": .string("x")])
    ])

    let openAIContent = try OpenAiCompatibleAgentModelToolProtocolAdapter(limits: limits)
      .encodeConversation([assistant, result])
      .requiredArray("messages")
      .requiredObject(1)
      .requiredString("content")
    try assertBoundedSummary(openAIContent, limit: limits.maxToolResultCharacters)

    let anthropicContent = try AnthropicAgentModelToolProtocolAdapter(limits: limits)
      .encodeConversation([assistant, result])
      .requiredArray("messages")
      .requiredObject(1)
      .requiredArray("content")
      .requiredObject(0)
      .requiredString("content")
    try assertBoundedSummary(anthropicContent, limit: limits.maxToolResultCharacters)

    let geminiResponse = try GeminiAgentModelToolProtocolAdapter(limits: limits)
      .encodeConversation([assistant, result])
      .requiredArray("contents")
      .requiredObject(1)
      .requiredArray("parts")
      .requiredObject(0)
      .requiredObject("functionResponse")
    let geminiSummary = try geminiResponse.requiredObject("response")
    XCTAssertLessThanOrEqual(AgentMcpJSONCodec.stringify(geminiSummary).count, limits.maxToolResultCharacters)
    XCTAssertEqual(try geminiSummary.requiredBool("truncated"), true)
    XCTAssertEqual(try geminiResponse.requiredString("id"), "bounded-call")
  }

  func testGeminiCreatesStableIdsOnlyWhenProviderOmitsOptionalId() throws {
    let adapter = GeminiAgentModelToolProtocolAdapter()
    let responseJSON = #"""
      {
        "responseId":"without-call-id",
        "candidates":[{"content":{"parts":[{"functionCall":{
          "name":"\#(Self.echoToolId)","args":{"value":"hello"}
        }}]},"finishReason":"STOP"}]
      }
      """#

    let first = try adapter.decodeResponse(responseJSON, catalog: testCatalog()).toolCalls.singleValue().callId
    let second = try adapter.decodeResponse(responseJSON, catalog: testCatalog()).toolCalls.singleValue().callId

    XCTAssertEqual(first, second)
    XCTAssertTrue(first.hasPrefix("gemini_call_"))
    XCTAssertFalse(first.isEmpty)
  }

  func testAgentModelToolProtocolModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentModelResponse.self,
      from: Data(
        #"""
        {
          "assistant_text": "Done",
          "tool_calls": [{
            "call_id": "call-1",
            "tool_id": "phone.test.echo",
            "tool_version": "1.0.0",
            "arguments": {"value": "ok"}
          }],
          "usage": {"input_tokens": 1, "output_tokens": 2},
          "provider_metadata": {"provider": "openai_compatible"}
        }
        """#.utf8
      )
    )
    let provider = try JSONDecoder().decode(
      AgentModelToolProvider.self,
      from: Data(#""anthropic""#.utf8)
    )
    let limits = try JSONDecoder().decode(
      AgentModelToolProtocolLimits.self,
      from: Data(#"{"max_tool_calls":4,"max_json_depth":8}"#.utf8)
    )
    let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)

    XCTAssertEqual(provider, .anthropic)
    XCTAssertEqual(limits.maxToolCalls, 4)
    XCTAssertEqual(limits.maxArgumentsCharacters, 65_536)
    XCTAssertEqual(decoded.toolCalls.singleValue().toolVersion, "1.0.0")
    XCTAssertEqual(decoded.usage.totalTokens, 3)
    XCTAssertTrue(encoded.contains(#""assistant_text":"Done""#))
    XCTAssertTrue(encoded.contains(#""tool_version":"1.0.0""#))
  }

  private func assertBoundedSummary(_ content: String, limit: Int) throws {
    XCTAssertLessThanOrEqual(content.count, limit)
    let data = Data(content.utf8)
    let decoded = try JSONDecoder().decode(AgentMcpJSONValue.self, from: data)
    let object = try XCTUnwrap(decoded.objectValue)
    XCTAssertEqual(object["truncated"], .bool(true))
    XCTAssertEqual(object["tool_call_id"], .string("bounded-call"))
  }

  private func expectProtocolError(_ code: String, block: () throws -> Void) {
    do {
      try block()
      XCTFail("Expected AgentModelToolProtocolError with code \(code)")
    } catch let error as AgentModelToolProtocolError {
      XCTAssertEqual(error.code, code)
    } catch {
      XCTFail("Expected AgentModelToolProtocolError with code \(code), got \(error)")
    }
  }

  private func toolResult(
    _ callId: String,
    _ toolId: String,
    status: String = "succeeded",
    output: AgentMcpJSONObject,
    message: String = ""
  ) -> AgentModelMessage {
    AgentModelMessage.tool(AgentModelToolResultContent(
      callId: callId,
      toolId: toolId,
      status: status,
      output: output,
      message: message
    ))
  }

  private func testCatalog() throws -> [AgentNativeToolDescriptor] {
    [
      try descriptor(
        id: Self.echoToolId,
        inputSchema: [
          "type": .string("object"),
          "properties": .object(["value": .object(["type": .string("string")])]),
          "required": .array([.string("value")]),
          "additionalProperties": .bool(false)
        ]
      ),
      try descriptor(
        id: Self.sumToolId,
        inputSchema: [
          "type": .string("object"),
          "properties": .object([
            "left": .object(["type": .string("integer")]),
            "right": .object(["type": .string("integer")])
          ]),
          "required": .array([.string("left"), .string("right")]),
          "additionalProperties": .bool(false)
        ]
      )
    ]
  }

  private func descriptor(id: String, inputSchema: AgentMcpJSONObject) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id,
      description: "Test adapter tool \(id).",
      location: .phone,
      inputSchema: inputSchema,
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: .low
    )
  }

  private static let echoToolId = "phone.test.echo"
  private static let sumToolId = "phone.test.sum"
}

private extension Dictionary where Key == String, Value == AgentMcpJSONValue {
  func requiredString(_ key: String) throws -> String {
    guard let value = self[key]?.strictStringValue else {
      throw AgentModelToolProtocolTestJSONError.missing("Expected string at \(key)")
    }
    return value
  }

  func requiredBool(_ key: String) throws -> Bool {
    guard let value = self[key]?.boolValue else {
      throw AgentModelToolProtocolTestJSONError.missing("Expected bool at \(key)")
    }
    return value
  }

  func requiredObject(_ key: String) throws -> AgentMcpJSONObject {
    guard let value = self[key]?.objectValue else {
      throw AgentModelToolProtocolTestJSONError.missing("Expected object at \(key)")
    }
    return value
  }

  func requiredArray(_ key: String) throws -> [AgentMcpJSONValue] {
    guard let value = self[key]?.arrayValue else {
      throw AgentModelToolProtocolTestJSONError.missing("Expected array at \(key)")
    }
    return value
  }
}

private extension Array where Element == AgentMcpJSONValue {
  func requiredObject(_ index: Int) throws -> AgentMcpJSONObject {
    guard indices.contains(index), let value = self[index].objectValue else {
      throw AgentModelToolProtocolTestJSONError.missing("Expected object at index \(index)")
    }
    return value
  }
}

private enum AgentModelToolProtocolTestJSONError: Error {
  case missing(String)
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
