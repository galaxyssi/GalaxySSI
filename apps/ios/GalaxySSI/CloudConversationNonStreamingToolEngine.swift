import Foundation

struct CloudConversationNonStreamingToolEngine {
  private let modelClient: CloudModelClient
  private let toolExecutor: CloudConversationToolExecuting

  init(
    modelClient: CloudModelClient,
    toolExecutor: CloudConversationToolExecuting = CloudWebGroundingToolExecutor()
  ) {
    self.modelClient = modelClient
    self.toolExecutor = toolExecutor
  }

  func reply(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload],
    requestId: String
  ) async throws -> String {
    let request = try await modelClient.prepareConversationStreamRequest(
      contact: contact,
      store: store,
      turns: turns,
      requestId: requestId,
      images: images
    )
    var conversation = try CloudModelStreamMutableConversation(request: request)
    var evidence: [(String, String)] = []
    let progress = CloudWebToolLoopProgress()
    var round = 0

    while true {
      let currentRound = round
      round += 1
      let finalRound = progress.finalizationRequested
      let roundRequest = try conversation.requestForRound(
        roundId: "\(requestId):compat-r\(currentRound)",
        finalRound: finalRound
      )
      let response = try await complete(roundRequest)
      let inline = response.calls.isEmpty
        ? CloudWebGrounding.parseInlineToolCalls(response.text)
        : []
      let usesInline = response.calls.isEmpty && !inline.isEmpty
      let calls = usesInline ? inline.enumerated().map { index, call in
        AssembledToolCall(
          callId: "compat-inline-r\(currentRound)-\(index)",
          index: index,
          name: call.name,
          argumentsJson: AgentMcpJSONCodec.stringify(call.arguments)
        )
      } : response.calls

      if calls.isEmpty {
        if CloudWebGrounding.containsInternalToolProtocol(response.text),
           !finalRound,
           progress.requestRepair("nonstream_internal_protocol") {
          conversation.appendInlineToolRepairPrompt(response.text)
          continue
        }
        let candidate = CloudWebGrounding.stripInternalToolProtocol(response.text)
        if let repair = CloudWebGrounding.citationRepairPrompt(candidate, results: evidence),
           !candidate.isBlank,
           !finalRound,
           progress.requestRepair("nonstream_citations") {
          conversation.appendCitationRepairPrompt(draft: candidate, prompt: repair)
          continue
        }
        if !candidate.isBlank,
           !CloudWebGrounding.citationValidation(candidate, results: evidence).requiresRepair {
          return candidate
        }
        return CloudWebGrounding.evidenceFallback(results: evidence)
      }

      if finalRound {
        if !evidence.isEmpty { return CloudWebGrounding.evidenceFallback(results: evidence) }
        throw GalaxySSIError.unsupportedResponse
      }

      var parsedCalls: [(AssembledToolCall, AgentMcpJSONObject)] = []
      var invalidToolCall: AssembledToolCall?
      for call in calls {
        guard let arguments = try? CloudModelStreamJSON.mcpObject(from: call.argumentsJson) else {
          invalidToolCall = call
          break
        }
        parsedCalls.append((call, arguments))
      }
      if let invalidToolCall {
        let repairKey = "nonstream_tool_arguments:\(invalidToolCall.name.lowercased())"
        if progress.requestRepair(repairKey) {
          conversation.appendToolArgumentRepairPrompt(invalidToolCall)
        } else {
          progress.requestFinalization()
        }
        continue
      }

      var results: [(AssembledToolCall, String)] = []
      var madeProgress = false
      for (call, arguments) in parsedCalls {
        if let output = progress.cached(toolName: call.name, arguments: arguments) {
          results.append((call, output))
          continue
        }
        let output = try toolExecutor.executeTool(
          call: call,
          context: CloudConversationToolExecutionContext(
            requestId: requestId,
            conversationId: turns.last?.conversationId ?? "",
            turnId: turns.last?.turnId ?? requestId
          )
        )
        results.append((call, output))
        if progress.record(toolName: call.name, arguments: arguments, output: output) {
          madeProgress = true
          evidence.append((call.name, output))
        }
      }
      if usesInline {
        conversation.appendInlineToolResults(response.text, results: results)
      } else {
        try conversation.appendToolResults(results)
      }
      if !madeProgress {
        progress.requestFinalization()
      }
    }
  }

  private func complete(_ request: ModelStreamRequest) async throws -> ParsedResponse {
    let body = try compatibilityBody(request.bodyJson, provider: request.provider)
    guard let url = compatibilityURL(request.endpoint, provider: request.provider) else {
      throw GalaxySSIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = Data(body.utf8)
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
    let object = try await modelClient.responseObject(for: urlRequest, throwHTTPFailure: true)
    return parse(object, provider: request.provider)
  }

  private func compatibilityBody(_ encoded: String, provider: ModelStreamProvider) throws -> String {
    var body = try CloudModelStreamJSON.object(from: encoded)
    if provider != .gemini { body["stream"] = false }
    return try CloudModelStreamJSON.string(body)
  }

  private func compatibilityURL(_ endpoint: String, provider: ModelStreamProvider) -> URL? {
    guard provider == .gemini, var components = URLComponents(string: endpoint) else {
      return URL(string: endpoint)
    }
    components.path = components.path.replacingOccurrences(
      of: ":streamGenerateContent",
      with: ":generateContent"
    )
    components.queryItems = (components.queryItems ?? []).filter { $0.name != "alt" }
    return components.url
  }

  private func parse(_ object: [String: Any], provider: ModelStreamProvider) -> ParsedResponse {
    switch provider {
    case .openAICompatible:
      return parseOpenAI(object)
    case .anthropic:
      return parseAnthropic(object)
    case .gemini:
      return parseGemini(object)
    }
  }

  private func parseOpenAI(_ object: [String: Any]) -> ParsedResponse {
    let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
    let text = (message?["content"] as? String) ?? (object["output_text"] as? String) ?? ""
    let calls = (message?["tool_calls"] as? [[String: Any]] ?? []).enumerated().compactMap { index, item in
      guard let function = item["function"] as? [String: Any],
            let name = function["name"] as? String, !name.isBlank else { return nil }
      return AssembledToolCall(
        callId: (item["id"] as? String ?? "").ifBlank("compat-openai-\(index)"),
        index: index,
        name: name,
        argumentsJson: (function["arguments"] as? String ?? "").ifBlank("{}")
      )
    }
    return ParsedResponse(text: text, calls: calls)
  }

  private func parseAnthropic(_ object: [String: Any]) -> ParsedResponse {
    let blocks = object["content"] as? [[String: Any]] ?? []
    let text = blocks.compactMap { block -> String? in
      guard (block["type"] as? String) == "text" else { return nil }
      return block["text"] as? String
    }.joined(separator: "\n")
    let calls = blocks.enumerated().compactMap { index, block -> AssembledToolCall? in
      guard (block["type"] as? String) == "tool_use",
            let name = block["name"] as? String, !name.isBlank else { return nil }
      return AssembledToolCall(
        callId: (block["id"] as? String ?? "").ifBlank("compat-anthropic-\(index)"),
        index: index,
        name: name,
        argumentsJson: jsonString(block["input"])
      )
    }
    return ParsedResponse(text: text, calls: calls)
  }

  private func parseGemini(_ object: [String: Any]) -> ParsedResponse {
    let content = (object["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any]
    let parts = content?["parts"] as? [[String: Any]] ?? []
    let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
    let calls = parts.enumerated().compactMap { index, part -> AssembledToolCall? in
      guard let function = part["functionCall"] as? [String: Any],
            let name = function["name"] as? String, !name.isBlank else { return nil }
      return AssembledToolCall(
        callId: "compat-gemini-\(index)-\(name)",
        index: index,
        name: name,
        argumentsJson: jsonString(function["args"])
      )
    }
    return ParsedResponse(text: text, calls: calls)
  }

  private func jsonString(_ value: Any?) -> String {
    guard let value, JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let result = String(data: data, encoding: .utf8) else { return "{}" }
    return result
  }

  private struct ParsedResponse {
    var text: String
    var calls: [AssembledToolCall]
  }

}
