import Foundation

struct CloudConversationNonStreamingToolEngine {
  private let modelClient: CloudModelClient
  private let toolExecutor: CloudConversationToolExecuting

  init(
    modelClient: CloudModelClient,
    toolExecutor: CloudConversationToolExecuting = CloudConversationToolExecutor()
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
    defer { CloudImageAnnotationSession.discard(requestId: requestId) }
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
    let research = CloudResearchRuntimeBudget(limits: .configured(contact.cloud_research_limits))
    let evidencePromptLedger = CloudEvidencePromptLedger(query: turns.last?.content ?? "")
    var round = 0

    while true {
      try Task.checkCancellation()
      if !progress.finalizationRequested, let reason = research.stopReason {
        progress.requestFinalization()
        conversation.appendResearchGuidance(research.guidance(stopped: reason))
      }
      let currentRound = round
      round += 1
      research.beginRound()
      let finalRound = progress.finalizationRequested
      let roundRequest = try conversation.requestForRound(
        roundId: "\(requestId):compat-r\(currentRound)",
        finalRound: finalRound
      )
      let response: ParsedResponse
      do {
        response = try await CloudResearchRoundDeadline.run(millis: research.limits.modelMillis) {
          try await complete(roundRequest)
        }
      } catch {
        try Task.checkCancellation()
        guard CloudResearchRuntimeBudget.canRecover(error) else { throw error }
        let hasEvidence = CloudResearchRuntimeBudget.hasCitableEvidence(evidence)
        if research.requestInterruptedSynthesis(hasEvidence: hasEvidence, finalizing: finalRound) {
          progress.requestFinalization()
          conversation.appendResearchGuidance(research.guidance(stopped: "model_round_interrupted"))
          continue
        }
        if hasEvidence { return CloudWebGrounding.evidenceFallback(results: evidence) }
        throw error
      }
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

      if calls.isEmpty, !CloudWebGrounding.containsInternalToolProtocol(response.text),
         research.requestEmptySynthesis(response.text, hasEvidence: CloudResearchRuntimeBudget.hasCitableEvidence(evidence)) {
        progress.requestFinalization()
        conversation.appendResearchGuidance(research.guidance(stopped: "empty_synthesis"))
        continue
      }
      if calls.isEmpty {
        if CloudWebGrounding.containsInternalToolProtocol(response.text),
           !finalRound,
           progress.requestFormatRepair("nonstream_internal_protocol") {
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
           let qualityReview = CloudResearchQualityStandard.repairIfNeeded(candidate, evidence: evidence),
           !CloudWebGrounding.citationValidation(candidate, results: evidence).requiresRepair {
          if progress.requestRepair("nonstream_research_quality") {
            conversation.appendResearchQualityRepair(draft: candidate, prompt: qualityReview)
            progress.requestFinalization()
            continue
          }
          return CloudWebGrounding.evidenceFallback(results: evidence) +
            CloudImageAnnotationSession.artifactSuffix(requestId: requestId)
        }
        if !candidate.isBlank,
           !CloudWebGrounding.citationValidation(candidate, results: evidence).requiresRepair {
          return candidate + CloudImageAnnotationSession.artifactSuffix(requestId: requestId)
        }
        return CloudWebGrounding.evidenceFallback(results: evidence) +
          CloudImageAnnotationSession.artifactSuffix(requestId: requestId)
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
        if progress.requestFormatRepair(repairKey) {
          conversation.appendToolArgumentRepairPrompt(invalidToolCall)
        } else {
          progress.requestFinalization()
        }
        continue
      }

      var results: [(AssembledToolCall, String)] = []
      var madeProgress = false
      var newResearchEvidence = false
      let retrievalBatch = parsedCalls.contains { CloudResearchRuntimeBudget.isRetrievalTool($0.0.name) }
      let uncached = Set(parsedCalls.compactMap { call, arguments in
        progress.cached(toolName: call.name, arguments: arguments) == nil
          ? progress.semanticKey(toolName: call.name, arguments: arguments) : nil
      })
      guard research.reserveTools(uncached.count) else {
        progress.requestFinalization()
        conversation.appendResearchGuidance(research.guidance(stopped: research.stopReason ?? "tool_batch_limit"))
        continue
      }
      for (call, arguments) in parsedCalls {
        try Task.checkCancellation()
        if let output = progress.cached(toolName: call.name, arguments: arguments) {
          CloudImageAnnotationSession.selectResult(output, requestId: requestId)
          results.append((call, output))
          continue
        }
        let output = try toolExecutor.executeTool(
          call: call,
          context: CloudConversationToolExecutionContext(
            requestId: requestId,
            researchToolTimeoutMillis: research.limits.toolMillis,
            conversationId: turns.last?.conversationId ?? "",
            turnId: turns.last?.turnId ?? requestId,
            images: images
          )
        )
        results.append((call, output))
        if progress.record(toolName: call.name, arguments: arguments, output: output) {
          newResearchEvidence = research.observe(tool: call.name, output: output) || newResearchEvidence
          madeProgress = true
          if call.name.lowercased() != CloudImageAnnotationPlan.toolName {
            evidence.append((call.name, output))
          }
        }
      }
      let rawEvidence = evidence.map(\.1)
      let projections = Dictionary(zip(rawEvidence, evidencePromptLedger.project(rawEvidence)),
        uniquingKeysWith: { first, _ in first })
      let promptResults = results.map { call, output in (call, projections[output] ?? evidencePromptLedger.project(output)) }
      if usesInline {
        conversation.appendInlineToolResults(response.text, results: promptResults)
      } else {
        try conversation.appendToolResults(promptResults)
      }
      if retrievalBatch {
        research.finishRetrievalBatch(madeProgress: newResearchEvidence)
        if research.stopReason == nil { conversation.appendResearchGuidance(research.guidance()) }
      } else if !madeProgress {
        progress.requestFinalization()
      }
    }
  }

  private func complete(_ request: ModelStreamRequest) async throws -> ParsedResponse {
    let body = try Self.compatibilityBody(request.bodyJson, provider: request.provider)
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

  static func compatibilityBody(_ encoded: String, provider: ModelStreamProvider) throws -> String {
    var body = try CloudModelStreamJSON.object(from: encoded)
    if provider != .gemini { body["stream"] = false }
    else { body.removeValue(forKey: "stream") }
    body.removeValue(forKey: "stream_options")
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
    let calls = (message?["tool_calls"] as? [[String: Any]] ?? []).enumerated().compactMap {
      index, item -> AssembledToolCall? in
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

  private struct ParsedResponse: Sendable {
    var text: String
    var calls: [AssembledToolCall]
  }

}
