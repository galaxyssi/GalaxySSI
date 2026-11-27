import Foundation

enum AgentConversationGoalInference {
  static func system(review: Bool, language: String) -> String {
    "Work on one persistent text-only goal. Produce concrete new work in language " + String(language.prefix(32)) + ". " +
    "Only the objective, checkpoints and explicit user clarification are available. No tools, web access, device actions, " +
    "other chats or health records. Never claim actions, searches or external verification that you did not perform. " +
    "If an external action, fresh source, permission or missing input is essential, return blocked and specify what is needed. " +
    "Return exactly one JSON object: state (continue, done, blocked), result (new work or the full final deliverable, not a promise), " +
    "next (next step or specific blocking question). No executable rich content. Finish promptly once the objective is met." +
    (review ? " This is a separate FINAL REVIEW. Inspect the last checkpoint against the FULL objective and clarification. " +
      "Only if complete, return exactly {\"state\":\"verified\",\"result\":\"\",\"next\":\"\"}. Promises and unsupported external claims do not pass. " +
      "Otherwise return continue with concrete corrections or blocked. Do not return done." : "")
  }
  static func prompt(_ goal: AgentConversationGoal) throws -> String {
    guard goal.valid, goal.inFlight else { throw AgentConversationGoal.Failure.invalid }
    let history = goal.checkpoints.enumerated().map { index, text in
      goal.review && index == goal.checkpoints.count - 1 ? text : String(text.prefix(index >= goal.checkpoints.count - 2 ? 8_000 : 480))
    }
    let body: [String: Any] = ["objective": goal.objective, "checkpoints": history, "pending": goal.next,
      "clarification": goal.clarification, "remaining_rounds": goal.allowance - goal.rounds]
    return String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), as: UTF8.self)
  }
  static func fingerprint(contact: GalaxySSIContact, model: CloudModelConfig) -> String {
    AgentModelLoopRecoveryIdentity.sha256(["contact": contact.id, "provider": contact.cloudProvider,
      "model": model.modelId, "endpoint": model.endpoint, "api_style": model.apiStyle.rawValue])
  }
  static func fingerprint(profile: LocalModelRuntimeProfile) -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(profile) else { return "" }
    return AgentBlobProtocol.sha256(data)
  }
  static func isolatedRequest(_ prepared: ModelStreamRequest, system: String) throws -> ModelStreamRequest {
    var request = try AgentSingleFileRead.isolatedRequest(prepared, system: system)
    guard var body = try JSONSerialization.jsonObject(with: Data(request.bodyJson.utf8)) as? [String: Any] else { throw AgentConversationGoal.Failure.invalid }
    switch request.provider {
    case .gemini:
      var config = body["generationConfig"] as? [String: Any] ?? [:]; config["maxOutputTokens"] = 3_000
      body["generationConfig"] = config
    case .openAICompatible:
      body.removeValue(forKey: "max_tokens"); body.removeValue(forKey: "max_completion_tokens")
      body[URLComponents(string: request.endpoint)?.host?.lowercased() == "api.openai.com" ? "max_completion_tokens" : "max_tokens"] = 3_000
      body["store"] = false
    case .anthropic: body["max_tokens"] = 3_000
    }
    request.bodyJson = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    return request
  }
  @MainActor static func isCurrent(_ route: AgentConversationGoal.Route, store: GalaxySSIStore) -> Bool {
    if route.kind == .local {
      return LocalModelRuntimeSettings.activeProfiles(defaults: store.defaults).contains {
        $0.id == route.model && route.artifactSHA == fingerprint(profile: $0)
      }
    }
    let disclosure = FileAgentDataDisclosureStore(fileURL: AgentDataDisclosureStorePaths.ledgerURL())
    guard let contact = store.contact(id: route.target), !contact.deleted, contact.deliveryMode == .cloudAPI,
      !disclosure.blockedDestinationIds().contains(contact.id) else { return false }
    return contact.cloudModels.contains { model in
      model.modelId == route.model && fingerprint(contact: contact, model: model) == route.endpointSHA &&
        AgentConnectorAvailability.cloudModelReady(model: model, apiKey: store.apiKey(for: model),
          provider: contact.cloudProvider, setupStatus: contact.setupStatus)
    }
  }
  @MainActor static func routes(store: GalaxySSIStore, conversation: String) -> [AgentConversationGoal.Route] {
    var result = LocalModelRuntimeSettings.activeProfiles(defaults: store.defaults).filter {
      LocalModelInferenceRuntime.shared.readyForBackground(profile: $0)
    }.map { AgentConversationGoal.Route(kind: .local, target: "local-llm", model: $0.id, endpointSHA: "", host: "", artifactSHA: fingerprint(profile: $0)) }
    let disclosure = FileAgentDataDisclosureStore(fileURL: AgentDataDisclosureStorePaths.ledgerURL())
    let blocked = disclosure.blockedDestinationIds()
    for contact in store.contacts where !contact.deleted && contact.deliveryMode == .cloudAPI && !blocked.contains(contact.id) {
      for model in contact.cloudModels where AgentConnectorAvailability.cloudModelReady(model: model,
        apiKey: store.apiKey(for: model), provider: contact.cloudProvider, setupStatus: contact.setupStatus) {
        guard let host = URLComponents(string: model.endpoint)?.host else { continue }
        let route = AgentConversationGoal.Route(kind: .cloud, target: contact.id, model: model.modelId,
          endpointSHA: fingerprint(contact: contact, model: model), host: host)
        if route.valid && !result.contains(route) { result.append(route) }
      }
    }
    let selected = AgentModelSelectionSettings.selection(for: conversation, defaults: store.defaults)
    return result.sorted {
      let a = $0.target == selected.targetId && (selected.modelId.isBlank || $0.model == selected.modelId)
      let b = $1.target == selected.targetId && (selected.modelId.isBlank || $1.model == selected.modelId)
      if a != b { return a }
      return ($0.target, $0.model) < ($1.target, $1.model)
    }
  }
  @MainActor static func step(_ goal: AgentConversationGoal, store: GalaxySSIStore,
    valid: () -> Bool) async throws -> String {
    guard valid(), isCurrent(goal.route, store: store) else { throw AgentConversationGoal.Failure.unavailable }
    let system = system(review: goal.review, language: LanguagePolicySettings.resolve(store.languagePolicy.responseLanguage))
    let prompt = try prompt(goal)
    let requestID = "conversation-goal-\(goal.id.uuidString)-\(goal.generation)-\(goal.rounds)"
    if goal.route.kind == .local {
      guard let profile = LocalModelRuntimeSettings.activeProfiles(defaults: store.defaults).first(where: { $0.id == goal.route.model }),
        LocalModelInferenceRuntime.shared.readyForBackground(profile: profile) else { throw AgentConversationGoal.Failure.unavailable }
      let cancellation = AgentModelToolLoopCancellationSource()
      return try await withTaskCancellationHandler(operation: {
        let result = try await LocalModelInferenceRuntime.shared.generateAsync(profile: profile, systemPrompt: system,
          userPrompt: prompt, maximumTokens: 2_048, temperature: 0.2, workClass: .background,
          taskId: requestID, cancellation: cancellation.token)
        guard valid(), !Task.isCancelled else { throw CancellationError() }
        return result.text
      }, onCancel: { cancellation.cancel() })
    }
    guard let contact = store.contact(id: goal.route.target), contact.deliveryMode == .cloudAPI, !contact.deleted,
      let model = contact.cloudModels.first(where: { $0.modelId == goal.route.model && fingerprint(contact: contact, model: $0) == goal.route.endpointSHA }),
      let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key) else { throw AgentConversationGoal.Failure.unavailable }
    let probe = AgentMediaNetworkDetector.shared.currentProbe
    let budget = AgentTaskBudgetPolicy.evaluate(budget: store.agentTaskBudget,
      usage: .init(networkBytes: Int64(system.utf8.count + prompt.utf8.count), usageEstimated: true),
      environment: .init(networkAvailable: probe.networkPresent && probe.internetCapable && probe.validated,
        networkValidated: probe.validated, networkMetered: probe.metered), networkRequired: true, trustedNetworkTarget: true)
    guard budget.allowed else { throw AgentConversationGoal.Failure.unavailable }
    let disclosure = FileAgentDataDisclosureStore(fileURL: AgentDataDisclosureStorePaths.ledgerURL())
    var selected = contact; selected.cloudModels = [model]; selected.selectedCloudModelId = model.modelId
    let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: disclosure, destination: .init(contact: selected),
      text: system + "\n" + prompt, historyCount: goal.checkpoints.count, systemInstructions: true,
      purpose: "Confirmed conversation text goal", conversationId: goal.conversation, taskId: goal.id.uuidString, turnId: requestID)
    guard ticket.allowed else { throw AgentDataDisclosureBlockedError(destination: contact.displayName) }
    let only = ChatMessage(contactId: "hermes", content: prompt, isMine: true, conversationId: goal.conversation, turnId: requestID)
    let prepared = try CloudModelClient().conversationStreamingRequest(model: model, apiKey: key, turns: [only],
      systemPrompt: system, requestId: requestID, images: [])
    let request = try isolatedRequest(prepared, system: system)
    let client = URLSessionCloudModelStreamClient()
    return try await withTaskCancellationHandler(operation: {
      var body = "", completed = false
      do {
        for try await event in client.stream(request) {
          try Task.checkCancellation()
          guard valid(), event.requestId == requestID,
            !disclosure.blockedDestinationIds().contains(contact.id) else { throw CancellationError() }
          switch event {
          case .textDelta(let delta):
            guard body.utf8.count + delta.text.utf8.count <= 131_072 else { throw AgentConversationGoal.Failure.invalid }
            body += delta.text
          case .completed(let final):
            if let reason = final.finishReason?.lowercased(), ["length", "max_tokens", "max_output_tokens", "tool_calls", "function_call"].contains(reason) {
              throw AgentConversationGoal.Failure.invalid
            }
            completed = true
          case .toolCallDelta, .failed: throw AgentConversationGoal.Failure.invalid
          default: break
          }
        }
        guard valid(), completed, !Task.isCancelled else { throw CancellationError() }
        AgentDataDisclosureLedger.update(store: disclosure, ticket: ticket, status: .sent)
        return body
      } catch {
        await client.cancel(requestId: requestID, reason: .userStop)
        AgentDataDisclosureLedger.update(store: disclosure, ticket: ticket, status: .failed)
        throw error
      }
    }, onCancel: { Task { await client.cancel(requestId: requestID, reason: .userStop) } })
  }
}
