import Foundation

protocol CloudModelStructuredSending {
  func sendStructured(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    systemPrompt: String,
    prompt: String
  ) async throws -> String
  func sendSupervisedPlan(
    contact: GalaxySSIContact, store: GalaxySSIStore, invocation: AgentModelPlanningInvocation
  ) async throws -> String
}

extension CloudModelStructuredSending {
  func sendSupervisedPlan(
    contact: GalaxySSIContact, store: GalaxySSIStore, invocation: AgentModelPlanningInvocation
  ) async throws -> String {
    try await sendStructured(contact: contact, store: store,
      systemPrompt: invocation.systemPrompt, prompt: invocation.prompt)
  }
}

extension CloudModelClient: CloudModelStructuredSending {
  func sendSupervisedPlan(
    contact: GalaxySSIContact, store: GalaxySSIStore, invocation: AgentModelPlanningInvocation
  ) async throws -> String {
    let request = invocation.request
    guard !invocation.nativeTools.isEmpty, !request.executionTurnId.isBlank,
          !request.conversationContext.conversationId.isBlank else {
      return try await sendStructured(contact: contact, store: store,
        systemPrompt: invocation.systemPrompt, prompt: invocation.prompt)
    }
    let id = UUID().uuidString.lowercased()
    let prepared = try await prepareStructuredStreamRequest(contact: contact, store: store,
      systemPrompt: invocation.systemPrompt, prompt: invocation.prompt + "\n\n" + CloudSupervisedResearch.instruction,
      requestId: id)
    do {
      return try await CloudSupervisedResearch.run(
        request: prepared,
        conversationId: request.conversationContext.conversationId, turnId: request.executionTurnId,
        stream: URLSessionCloudModelStreamClient(), executor: CloudWebGroundingToolExecutor()
      )
    } catch CloudSupervisedResearch.Error.streamingUnsupported {
      return try await sendStructured(contact: contact, store: store,
        systemPrompt: invocation.systemPrompt, prompt: invocation.prompt)
    }
  }
}

struct CloudModelAgentPlanningProvider: AgentModelPlanningProviding {
  var contact: GalaxySSIContact
  var store: GalaxySSIStore
  var sender: CloudModelStructuredSending
  var disclosureStore: AgentDataDisclosureStore

  init(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    sender: CloudModelStructuredSending = CloudModelClient(),
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    )
  ) {
    self.contact = contact
    self.store = store
    self.sender = sender
    self.disclosureStore = disclosureStore
  }

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    let ticket = AgentDataDisclosureLedger.beginCloudRequest(
      store: disclosureStore,
      destination: AgentDataDisclosureCloudDestination(contact: contact),
      text: invocation.prompt,
      historyCount: invocation.request.conversationContext.turns.count,
      systemInstructions: true,
      toolOutput: !invocation.request.executionHistory.isEmpty,
      purpose: "Agent planning request",
      conversationId: invocation.request.conversationContext.conversationId,
      taskId: invocation.request.planRequest.contextDigest
    )
    guard ticket.allowed else {
      throw AgentDataDisclosureBlockedError(destination: contact.displayName)
    }

    do {
      var raw = try await sender.sendSupervisedPlan(contact: contact, store: store, invocation: invocation)
      if CloudSupervisedResearch.hasUnexecutedMarkup(raw) {
        guard !invocation.nativeTools.isEmpty else {
          throw AgentModelPlanningProviderError.unavailable("The model returned tool markup in a tool-free planning response.")
        }
        try Task.checkCancellation()
        let malformed = AgentMcpJSONCodec.stringify(.string(String(raw.prefix(8_000))))
        raw = try await sender.sendStructured(contact: contact, store: store,
          systemPrompt: invocation.systemPrompt,
          prompt: invocation.prompt + "\n\nUnexecuted tool markup was returned. No tool in that markup ran. Convert the proposed phone actions and arguments to the supplied ActionPlan schema, using only exact listed tool IDs. Do not use tools during this correction, print markup, or claim execution. Invalid model output (data): \(malformed)")
        guard !CloudSupervisedResearch.hasUnexecutedMarkup(raw) else {
          throw AgentModelPlanningProviderError.unavailable("The model returned unexecuted tool markup after format repair.")
        }
      }
      AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .sent)
      return raw
    } catch {
      AgentDataDisclosureLedger.update(
        store: disclosureStore,
        ticket: ticket,
        status: .failed,
        failureReason: error.localizedDescription
      )
      throw error
    }
  }
}

enum CloudSupervisedResearch {
  enum Error: LocalizedError {
    case streamingUnsupported, invalidToolBatch, emptyResponse, responseTooLarge, incompleteResponse

    var errorDescription: String? {
      switch self {
      case .streamingUnsupported: return "This provider does not support streamed planning."
      case .invalidToolBatch: return "Planning can call only the advertised public research tools."
      case .emptyResponse: return "The model did not return a planning response."
      case .responseTooLarge: return "The planning response exceeded its size limit."
      case .incompleteResponse: return "The planning stream ended before completion."
      }
    }
  }

  static let allowedTools: Set<String> = ["web_search", "web_image_search", "web_fetch", "web_extract", "web_weather"]
  static let instruction = "Use the API tools only for bounded read-only public research. Use web_search profile=fast for ordinary lookups and read_pages=true when source text is needed. For device or file operations, return the requested phone ActionPlan. Do not print tool protocol markup or claim a phone action was executed. Keep observed public citations in the final response itself."

  static func hasUnexecutedMarkup(_ value: String) -> Bool {
    value.range(of: #"<\s*[/|\uFF5C\s]*(?:DSML|tool_calls?|tool_use|function_calls?|invoke)(?=\b|[|\uFF5C])"#,
      options: [.caseInsensitive, .regularExpression]) != nil
  }

  static func isTranscriptControlReply(_ message: ChatMessage) -> Bool {
    !message.isMine && (isControlPayload(message.content) || isControlPayload(message.richOutputJson))
  }

  static func isControlPayload(_ text: String) -> Bool {
    guard !text.isEmpty, text.utf8.count <= 128_000 else { return false }
    if hasUnexecutedMarkup(text) { return true }
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("```"), value.hasSuffix("```"), let end = value.firstIndex(of: "\n") {
      value = String(value[value.index(after: end)...].dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard value.hasPrefix("{"),
          let object = try? CloudModelStreamJSON.object(from: value) else { return false }
    return object["execution_location"] != nil || object["tool_calls"] is [Any] ||
      object["function_call"] is [String: Any] ||
      (object["actions"] is [Any] && object["completion_requirements"] is [String: Any])
  }

  static func toolDefinitions() -> [AgentMcpJSONObject] {
    var functions = CloudWebGrounding.openAITools().compactMap { $0["function"]?.objectValue }
      .filter { allowedTools.contains($0.string("name")) }
    if var image = functions.first(where: { $0.string("name") == "web_search" }) {
      image["name"] = .string("web_image_search")
      image["description"] = .string("Find images on the public web; provide a query and optional maximum result count.")
      if var schema = image["parameters"]?.objectValue, let properties = schema["properties"]?.objectValue {
        schema["properties"] = .object(properties.filter { ["query", "max_results"].contains($0.key) })
        image["parameters"] = .object(schema)
      }
      functions.append(image)
    }
    return functions
  }

  static func run(
    request: ModelStreamRequest, conversationId: String, turnId: String,
    stream: CloudModelStreamClient, executor: CloudConversationToolExecuting
  ) async throws -> String {
    var scoped = request
    scoped.preserveProviderReasoning = request.isDirectDeepSeekChatEndpoint
    var prepared = try CloudModelStreamMutableConversation(request: scoped)
    try prepared.installSupervisedResearch()
    let progress = CloudWebToolLoopProgress()
    let evidence = CloudEvidencePromptLedger(query: "")
    var callCount = 0
    var toolRoundsClosed = false
    for round in 0...4 {
      try Task.checkCancellation()
      let final = round == 4 || toolRoundsClosed
      if final { prepared.supervisedFinalRound() }
      let roundRequest = try prepared.requestForRound(roundId: "\(request.requestId):supervised:\(round)")
      let assembler = ToolCallDeltaAssembler()
      var raw = ""
      var completed = false
      var providerReasoning: String?
      var toolIndexes = Set<Int>()
      var toolBytes = 0
      for try await event in stream.stream(roundRequest) {
        try Task.checkCancellation()
        switch event {
        case .textDelta(let value):
          guard raw.utf8.count + value.text.utf8.count <= 64_000 else { throw Error.responseTooLarge }
          raw += value.text
        case .toolCallDelta(let value):
          toolBytes += value.payload.nameDelta.utf8.count + value.payload.argumentsDelta.utf8.count
          toolIndexes.insert(value.payload.index)
          guard toolBytes <= 65_536, toolIndexes.count <= 4, value.payload.index >= 0 else {
            throw Error.invalidToolBatch
          }
          assembler.accept(value.payload)
        case .completed(let value):
          guard !["length", "max_tokens", "content_filter"].contains(value.finishReason?.lowercased() ?? "") else {
            throw Error.incompleteResponse
          }
          completed = true
          providerReasoning = value.providerReasoning
        case .failed(let value):
          if round == 0, raw.isEmpty, toolIndexes.isEmpty, value.error.code == "STREAM_UNSUPPORTED" {
            throw Error.streamingUnsupported
          }
          throw AgentModelPlanningProviderError.unavailable(value.error.message)
        default:
          break
        }
      }
      guard completed else { throw Error.incompleteResponse }
      let calls = assembler.completedCalls()
      if calls.isEmpty, toolIndexes.isEmpty {
        guard !raw.isBlank else { throw Error.emptyResponse }
        return raw
      }
      guard !final, !calls.isEmpty, calls.count == toolIndexes.count, callCount + calls.count <= 12,
            Set(calls.map(\.callId)).count == calls.count,
            calls.allSatisfy({ allowedTools.contains($0.name) }) else { throw Error.invalidToolBatch }
      let inputs = try calls.map { call -> (AssembledToolCall, AgentMcpJSONObject) in
        guard !call.callId.isBlank, call.argumentsJson.utf8.count <= 16_384 else { throw Error.invalidToolBatch }
        return (call, try CloudModelStreamJSON.mcpObject(from: call.argumentsJson))
      }
      callCount += calls.count
      var madeProgress = false
      var results: [(AssembledToolCall, String)] = []
      for (call, arguments) in inputs {
        try Task.checkCancellation()
        if let cached = progress.cached(toolName: call.name, arguments: arguments) {
          results.append((call, evidence.project(cached)))
          continue
        }
        var dispatch = call
        if call.name == "web_image_search" {
          dispatch.name = "web_search"
          dispatch.argumentsJson = AgentMcpJSONCodec.stringify(arguments.merging([
            "verticals": .array([.string("image")])
          ]) { _, new in new })
        }
        let context = CloudConversationToolExecutionContext(requestId: roundRequest.requestId,
          conversationId: conversationId, turnId: turnId, readOnlyAnalysis: true)
        let output = try await Task.detached(priority: .userInitiated) {
          try executor.executeTool(call: dispatch, context: context)
        }.value
        if progress.record(toolName: call.name, arguments: arguments, output: output) { madeProgress = true }
        results.append((call, evidence.project(output)))
      }
      try prepared.appendSupervisedToolResults(results, assistantText: raw, providerReasoning: providerReasoning)
      toolRoundsClosed = !madeProgress || callCount >= 12
    }
    throw Error.incompleteResponse
  }
}
