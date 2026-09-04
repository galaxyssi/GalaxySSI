import Foundation

final class AnthropicAgentModelToolProtocolAdapter: StrictAgentModelToolProtocolAdapter {
  private let successStatuses = Set(["success", "succeeded"])

  init(limits: AgentModelToolProtocolLimits = .defaultLimits) {
    super.init(provider: .anthropic, limits: limits)
  }

  override func encodeToolCatalog(_ catalog: [AgentNativeToolDescriptor]) throws -> [AgentMcpJSONValue] {
    _ = try checkedCatalog(catalog)
    return catalog.map { descriptor in
      .object([
        "name": .string(descriptor.id),
        "description": .string(descriptor.description),
        "input_schema": .object(descriptor.inputSchema)
      ])
    }
  }

  override func encodeConversation(_ messages: [AgentModelMessage]) throws -> AgentMcpJSONObject {
    var result: AgentMcpJSONObject = [:]
    let systemText = messages
      .filter { $0.role == .system }
      .map(\.text)
      .filter { !$0.isBlank }
      .joined(separator: "\n\n")
    if !systemText.isBlank {
      result["system"] = .string(systemText)
    }

    var encoded: [AgentMcpJSONValue] = []
    var index = messages.startIndex
    while index < messages.endIndex {
      let message = messages[index]
      switch message.role {
      case .system:
        break
      case .user:
        encoded.append(.object([
          "role": .string("user"),
          "content": .array([textBlock(message.text)])
        ]))
      case .assistant:
        let path = "messages[\(index)]"
        var blocks: [AgentMcpJSONValue] = []
        if !message.text.isBlank {
          blocks.append(textBlock(message.text))
        }
        try checkCallCount(message.toolCalls.count, path: path)
        for (callIndex, call) in message.toolCalls.enumerated() {
          try checkedOutboundCall(call, path: "\(path).tool_calls[\(callIndex)]")
          blocks.append(.object([
            "type": .string("tool_use"),
            "id": .string(call.callId),
            "name": .string(call.toolId),
            "input": .object(call.arguments)
          ]))
        }
        encoded.append(.object(["role": .string("assistant"), "content": .array(blocks)]))
      case .tool:
        var blocks: [AgentMcpJSONValue] = []
        while index < messages.endIndex, messages[index].role == .tool {
          let path = "messages[\(index)]"
          guard let toolResult = messages[index].toolResult else {
            throw protocolError("malformed_tool_result", "\(path).tool_result is required")
          }
          let bounded = try boundedResult(toolResult, path: path)
          blocks.append(.object([
            "type": .string("tool_result"),
            "tool_use_id": .string(toolResult.callId),
            "content": .string(bounded.jsonText),
            "is_error": .bool(!successStatuses.contains(toolResult.status.lowercased()))
          ]))
          index += 1
        }
        encoded.append(.object(["role": .string("user"), "content": .array(blocks)]))
        continue
      }
      index += 1
    }
    result["messages"] = .array(encoded)
    return result
  }

  override func decodeResponse(
    _ responseJSON: String,
    catalog: [AgentNativeToolDescriptor]
  ) throws -> AgentModelResponse {
    let root = try parseRoot(responseJSON)
    let content = try root.protocolRequiredArray("content", path: "response")
    var text: [String] = []
    var callBlocks: [AgentMcpJSONValue] = []
    for index in content.indices {
      let block = try content.protocolRequiredObject(index, path: "response.content")
      let type = try block.protocolRequiredString("type", path: "response.content[\(index)]")
      switch type {
      case "text":
        let value = try block.protocolRequiredString("text", path: "response.content[\(index)]")
        if !value.isBlank {
          text.append(value)
        }
      case "tool_use":
        callBlocks.append(.object(block))
      default:
        break
      }
    }

    let calls = try parseCalls(callBlocks, catalog: catalog) { item, path in
      ParsedAgentModelToolCall(
        id: try item.protocolRequiredString("id", path: path),
        name: try item.protocolRequiredString("name", path: path),
        arguments: try checkedArguments(
          try item.protocolRequiredObject("input", path: path),
          path: "\(path).input"
        )
      )
    }

    let usage = try root.protocolOptionalObject("usage", path: "response")
    let inputTokens: Int64
    let outputTokens: Int64
    if let usage {
      let baseInputTokens = try usage.protocolTokenCount("input_tokens", path: "response.usage")
      let cacheCreationTokens = try usage.protocolTokenCount("cache_creation_input_tokens", path: "response.usage")
      let cacheReadTokens = try usage.protocolTokenCount("cache_read_input_tokens", path: "response.usage")
      inputTokens = AgentModelToolProtocolJSON.saturatingSum(
        baseInputTokens,
        cacheCreationTokens,
        cacheReadTokens
      )
      outputTokens = try usage.protocolTokenCount("output_tokens", path: "response.usage")
    } else {
      inputTokens = 0
      outputTokens = 0
    }
    let stopReason = try root.protocolOptionalString("stop_reason", path: "response")
    var providerMetadata = metadata(stopReason)
    if let stopReason {
      providerMetadata["stop_reason"] = .string(stopReason)
    }
    if let responseId = try root.protocolOptionalString("id", path: "response") {
      providerMetadata["response_id"] = .string(responseId)
    }
    if let model = try root.protocolOptionalString("model", path: "response") {
      providerMetadata["model"] = .string(model)
    }

    return try modelResponse(
      text: text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
      calls: calls,
      usage: AgentModelUsage(inputTokens: inputTokens, outputTokens: outputTokens),
      metadata: providerMetadata
    )
  }

  private func textBlock(_ text: String) -> AgentMcpJSONValue {
    .object(["type": .string("text"), "text": .string(text)])
  }
}
