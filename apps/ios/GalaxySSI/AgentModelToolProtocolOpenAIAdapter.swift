import Foundation

final class OpenAiCompatibleAgentModelToolProtocolAdapter: StrictAgentModelToolProtocolAdapter {
  init(limits: AgentModelToolProtocolLimits = .defaultLimits) {
    super.init(provider: .openAICompatible, limits: limits)
  }

  override func encodeToolCatalog(_ catalog: [AgentNativeToolDescriptor]) throws -> [AgentMcpJSONValue] {
    _ = try checkedCatalog(catalog)
    return catalog.map { descriptor in
      .object([
        "type": .string("function"),
        "function": .object([
          "name": .string(descriptor.id),
          "description": .string(descriptor.description),
          "parameters": .object(descriptor.inputSchema)
        ])
      ])
    }
  }

  override func encodeConversation(_ messages: [AgentModelMessage]) throws -> AgentMcpJSONObject {
    var encoded: [AgentMcpJSONValue] = []
    for (index, message) in messages.enumerated() {
      let path = "messages[\(index)]"
      switch message.role {
      case .system:
        encoded.append(textMessage(role: "system", text: message.text))
      case .user:
        encoded.append(textMessage(role: "user", text: message.text))
      case .assistant:
        var item: AgentMcpJSONObject = [
          "role": .string("assistant"),
          "content": message.text.isBlank ? .null : .string(message.text)
        ]
        if !message.toolCalls.isEmpty {
          try checkCallCount(message.toolCalls.count, path: path)
          item["tool_calls"] = .array(try message.toolCalls.enumerated().map { callIndex, call in
            try checkedOutboundCall(call, path: "\(path).tool_calls[\(callIndex)]")
            return .object([
              "id": .string(call.callId),
              "type": .string("function"),
              "function": .object([
                "name": .string(call.toolId),
                "arguments": .string(AgentMcpJSONCodec.stringify(call.arguments))
              ])
            ])
          })
        }
        encoded.append(.object(item))
      case .tool:
        guard let result = message.toolResult else {
          throw protocolError("malformed_tool_result", "\(path).tool_result is required")
        }
        let bounded = try boundedResult(result, path: path)
        encoded.append(.object([
          "role": .string("tool"),
          "tool_call_id": .string(result.callId),
          "content": .string(bounded.jsonText)
        ]))
      }
    }
    return ["messages": .array(encoded)]
  }

  override func decodeResponse(
    _ responseJSON: String,
    catalog: [AgentNativeToolDescriptor]
  ) throws -> AgentModelResponse {
    let root = try parseRoot(responseJSON)
    let choices = try root.protocolRequiredArray("choices", path: "response")
    if choices.isEmpty {
      throw protocolError("malformed_response", "OpenAI response has no choices")
    }
    let choice = try choices.protocolRequiredObject(0, path: "response.choices")
    let message = try choice.protocolOptionalObject("message", path: "response.choices[0]")
    let text: String
    if let message {
      let content = try parseOpenAIContent(
        message.protocolOptionalValue("content"),
        path: "response.choices[0].message.content"
      )
      if content.isBlank {
        text = try message.protocolOptionalString("refusal", path: "response.choices[0].message") ?? ""
      } else {
        text = content
      }
    } else {
      text = try choice.protocolOptionalString("text", path: "response.choices[0]") ?? ""
    }

    let toolCalls: [AgentModelToolCall]
    if let message,
       let rawCalls = try message.protocolOptionalArray("tool_calls", path: "response.choices[0].message") {
      toolCalls = try parseCalls(rawCalls, catalog: catalog) { item, path in
        if let type = try item.protocolOptionalString("type", path: path), type != "function" {
          throw protocolError("malformed_tool_call", "\(path).type must be function")
        }
        let function = try item.protocolRequiredObject("function", path: path)
        return ParsedAgentModelToolCall(
          id: try item.protocolRequiredString("id", path: path),
          name: try function.protocolRequiredString("name", path: "\(path).function"),
          arguments: try parseOpenAIArguments(function, path: "\(path).function")
        )
      }
    } else {
      toolCalls = []
    }

    let usage = try root.protocolOptionalObject("usage", path: "response")
    let inputTokens: Int64
    let outputTokens: Int64
    if let usage {
      inputTokens = try usage.protocolTokenCount(
        "prompt_tokens",
        fallbackKey: "input_tokens",
        path: "response.usage"
      )
      outputTokens = try usage.protocolTokenCount(
        "completion_tokens",
        fallbackKey: "output_tokens",
        path: "response.usage"
      )
    } else {
      inputTokens = 0
      outputTokens = 0
    }
    let finishReason = try choice.protocolOptionalString("finish_reason", path: "response.choices[0]")
      ?? (try choice.protocolOptionalString("finishReason", path: "response.choices[0]"))
    var providerMetadata = metadata(finishReason)
    if let responseId = try root.protocolOptionalString("id", path: "response") {
      providerMetadata["response_id"] = .string(responseId)
    }
    if let model = try root.protocolOptionalString("model", path: "response") {
      providerMetadata["model"] = .string(model)
    }

    return try modelResponse(
      text: text,
      calls: toolCalls,
      usage: AgentModelUsage(inputTokens: inputTokens, outputTokens: outputTokens),
      metadata: providerMetadata
    )
  }

  private func parseOpenAIArguments(
    _ function: AgentMcpJSONObject,
    path: String
  ) throws -> AgentMcpJSONObject {
    let value = try function.protocolRequiredValue("arguments", path: path)
    switch value {
    case .string(let string):
      return try parseArgumentString(string, path: "\(path).arguments")
    case .object(let object):
      return try checkedArguments(object, path: "\(path).arguments")
    default:
      throw protocolError(
        "malformed_tool_call",
        "\(path).arguments must be a JSON object or a JSON-encoded object"
      )
    }
  }

  private func parseOpenAIContent(_ value: AgentMcpJSONValue?, path: String) throws -> String {
    guard let value, value != .null else {
      return ""
    }
    switch value {
    case .string(let text):
      return text
    case .array(let blocks):
      var texts: [String] = []
      for (index, block) in blocks.enumerated() {
        switch block {
        case .string(let text) where !text.isBlank:
          texts.append(text)
        case .object(let object):
          let type = try object.protocolOptionalString("type", path: "\(path)[\(index)]")
          if type == nil || type == "text" || type == "output_text" {
            if let text = try object.protocolOptionalString("text", path: "\(path)[\(index)]"), !text.isBlank {
              texts.append(text)
            }
          }
        default:
          break
        }
      }
      return texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    case .null:
      return ""
    default:
      throw protocolError("malformed_response", "\(path) must be a string, array, or null")
    }
  }

  private func textMessage(role: String, text: String) -> AgentMcpJSONValue {
    .object(["role": .string(role), "content": .string(text)])
  }
}
