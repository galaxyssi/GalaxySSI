import Foundation

final class GeminiAgentModelToolProtocolAdapter: StrictAgentModelToolProtocolAdapter {
  init(limits: AgentModelToolProtocolLimits = .defaultLimits) {
    super.init(provider: .gemini, limits: limits)
  }

  override func encodeToolCatalog(_ catalog: [AgentNativeToolDescriptor]) throws -> [AgentMcpJSONValue] {
    _ = try checkedCatalog(catalog)
    let declarations = catalog.map { descriptor in
      AgentMcpJSONValue.object([
        "name": .string(descriptor.id),
        "description": .string(descriptor.description),
        "parameters": .object(descriptor.inputSchema),
        "response": .object(descriptor.outputSchema)
      ])
    }
    return [.object(["functionDeclarations": .array(declarations)])]
  }

  override func encodeConversation(_ messages: [AgentModelMessage]) throws -> AgentMcpJSONObject {
    var result: AgentMcpJSONObject = [:]
    let systemText = messages
      .filter { $0.role == .system }
      .map(\.text)
      .filter { !$0.isBlank }
      .joined(separator: "\n\n")
    if !systemText.isBlank {
      result["system_instruction"] = .object([
        "parts": .array([.object(["text": .string(systemText)])])
      ])
    }

    var contents: [AgentMcpJSONValue] = []
    var index = messages.startIndex
    while index < messages.endIndex {
      let message = messages[index]
      switch message.role {
      case .system:
        break
      case .user:
        contents.append(content(role: "user", parts: [textPart(message.text)]))
      case .assistant:
        let path = "messages[\(index)]"
        var parts: [AgentMcpJSONValue] = []
        if !message.text.isBlank {
          parts.append(textPart(message.text))
        }
        try checkCallCount(message.toolCalls.count, path: path)
        for (callIndex, call) in message.toolCalls.enumerated() {
          try checkedOutboundCall(call, path: "\(path).tool_calls[\(callIndex)]")
          parts.append(.object([
            "functionCall": .object([
              "id": .string(call.callId),
              "name": .string(call.toolId),
              "args": .object(call.arguments)
            ])
          ]))
        }
        contents.append(content(role: "model", parts: parts))
      case .tool:
        var parts: [AgentMcpJSONValue] = []
        while index < messages.endIndex, messages[index].role == .tool {
          let path = "messages[\(index)]"
          guard let toolResult = messages[index].toolResult else {
            throw protocolError("malformed_tool_result", "\(path).tool_result is required")
          }
          let bounded = try boundedResult(toolResult, path: path)
          parts.append(.object([
            "functionResponse": .object([
              "id": .string(toolResult.callId),
              "name": .string(toolResult.toolId),
              "response": .object(bounded.value)
            ])
          ]))
          index += 1
        }
        contents.append(content(role: "user", parts: parts))
        continue
      }
      index += 1
    }
    result["contents"] = .array(contents)
    return result
  }

  override func decodeResponse(
    _ responseJSON: String,
    catalog: [AgentNativeToolDescriptor]
  ) throws -> AgentModelResponse {
    let root = try parseRoot(responseJSON)
    let candidates = try root.protocolRequiredArray("candidates", path: "response")
    if candidates.isEmpty {
      throw protocolError("malformed_response", "Gemini response has no candidates")
    }
    let candidate = try candidates.protocolRequiredObject(0, path: "response.candidates")
    let content = try candidate.protocolRequiredObject("content", path: "response.candidates[0]")
    let parts = try content.protocolRequiredArray("parts", path: "response.candidates[0].content")

    var text: [String] = []
    var rawCalls: [(AgentMcpJSONObject, Int)] = []
    for index in parts.indices {
      let part = try parts.protocolRequiredObject(index, path: "response.candidates[0].content.parts")
      if let value = try part.protocolOptionalString(
        "text",
        path: "response.candidates[0].content.parts[\(index)]"
      ), !value.isBlank {
        text.append(value)
      }
      if let function = try part.protocolOptionalObject(
        "functionCall",
        path: "response.candidates[0].content.parts[\(index)]"
      ) {
        rawCalls.append((function, index))
      }
    }

    try checkCallCount(rawCalls.count, path: "response.candidates[0].content.parts")
    let catalogById = try checkedCatalog(catalog)
    var callIds = Set<String>()
    let providerResponseId = try root.protocolOptionalString("responseId", path: "response")
    let responseSeed = providerResponseId ?? AgentModelToolProtocolJSON.sha256(responseJSON)
    let calls = try rawCalls.enumerated().map { callIndex, entry in
      let function = entry.0
      let partIndex = entry.1
      let path = "response.candidates[0].content.parts[\(partIndex)].functionCall"
      do {
        let providerId = try function.protocolOptionalString("id", path: path)
        let callId = providerId ?? syntheticGeminiCallId(
          responseSeed: responseSeed,
          callIndex: callIndex,
          partIndex: partIndex
        )
        let name = try function.protocolRequiredString("name", path: path)
        let arguments: AgentMcpJSONObject
        if let args = function.protocolOptionalValue("args") {
          guard let object = args.objectValue else {
            throw protocolError("malformed_tool_call", "\(path).args must be a JSON object")
          }
          arguments = try checkedArguments(object, path: "\(path).args")
        } else {
          arguments = [:]
        }
        return try checkedParsedCall(
          ParsedAgentModelToolCall(id: callId, name: name, arguments: arguments),
          path: path,
          catalogById: catalogById,
          callIds: &callIds
        )
      } catch let error as AgentModelToolProtocolError {
        throw error.asMalformedToolCall(path: path)
      }
    }

    let usage = try root.protocolOptionalObject("usageMetadata", path: "response")
    let finishReason = try candidate.protocolOptionalString("finishReason", path: "response.candidates[0]")
    var providerMetadata = metadata(finishReason)
    if let responseId = try root.protocolOptionalString("responseId", path: "response") {
      providerMetadata["response_id"] = .string(responseId)
    }
    if let modelVersion = try root.protocolOptionalString("modelVersion", path: "response") {
      providerMetadata["model_version"] = .string(modelVersion)
    }
    let inputTokens: Int64
    let outputTokens: Int64
    if let usage {
      inputTokens = try usage.protocolTokenCount("promptTokenCount", path: "response.usageMetadata")
      if usage.protocolOptionalValue("candidatesTokenCount") != nil {
        outputTokens = try usage.protocolTokenCount("candidatesTokenCount", path: "response.usageMetadata")
      } else {
        outputTokens = try geminiOutputFromTotal(usage)
      }
    } else {
      inputTokens = 0
      outputTokens = 0
    }

    return try modelResponse(
      text: text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
      calls: calls,
      usage: AgentModelUsage(inputTokens: inputTokens, outputTokens: outputTokens),
      metadata: providerMetadata
    )
  }

  private func syntheticGeminiCallId(responseSeed: String, callIndex: Int, partIndex: Int) -> String {
    let digest = AgentModelToolProtocolJSON.sha256("\(responseSeed):\(callIndex):\(partIndex)")
    return "gemini_call_\(digest.prefix(24))"
  }

  private func geminiOutputFromTotal(_ usage: AgentMcpJSONObject?) throws -> Int64 {
    guard let usage else {
      return 0
    }
    let total = try usage.protocolTokenCount("totalTokenCount", path: "response.usageMetadata")
    let input = try usage.protocolTokenCount("promptTokenCount", path: "response.usageMetadata")
    return max(0, total - input)
  }

  private func textPart(_ text: String) -> AgentMcpJSONValue {
    .object(["text": .string(text)])
  }

  private func content(role: String, parts: [AgentMcpJSONValue]) -> AgentMcpJSONValue {
    .object(["role": .string(role), "parts": .array(parts)])
  }
}
