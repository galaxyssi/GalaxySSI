import Foundation

@MainActor
final class GalaxySSIHealthCareNativeToolSession {
  static let caller = "galaxyssi.health.discussion.native.v1"
  let approval: GalaxySSIHealthCareDiscussion.Approval
  let records: GalaxySSIHealthRecords
  let template: URLRequest
  let style: GalaxySSICloudAPIStyle
  let catalog: [AgentNativeToolDescriptor]
  let conversationID: String
  let workspaceID: String
  let currentDestination: () -> GalaxySSIContact?
  let cancellation = AgentModelToolLoopCancellationSource()
  var pending: AgentModelToolCall?

  init(approval: GalaxySSIHealthCareDiscussion.Approval, records: GalaxySSIHealthRecords,
      request: URLRequest, style: GalaxySSICloudAPIStyle,
      currentDestination: @escaping () -> GalaxySSIContact?) throws {
    guard approval.research == nil, approval.model?.apiStyle == style,
          request.httpMethod == "POST", request.url == approval.endpoint else { throw GalaxySSIHealthRecords.Failure.permission }
    self.approval = approval
    self.records = records
    template = request
    self.style = style
    self.currentDestination = currentDestination
    let execution = try records.careDiscussionExecution(approval)
    conversationID = execution.agentConversationID ?? approval.threadID.uuidString
    workspaceID = "private:" + AgentModelLoopRecoveryIdentity.sha256(["owner": approval.owner,
      "thread": approval.threadID.uuidString, "turn": approval.id.uuidString])
    catalog = try Self.descriptors(request, style: style, approval: approval)
  }

  func registry() throws -> AgentNativeToolRegistry {
    let registry = try AgentNativeToolRegistry(replayStore: InMemoryAgentNativeToolReplayStore(),
      auditStore: InMemoryAgentNativeToolAuditStore())
    for descriptor in catalog {
      let definition = AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: Self.caller)
      try registry.registerExecutable(.init(definition: definition, executor: { [weak self] invocation in
        let execute: @MainActor () throws -> AgentNativeToolExecutionResult = {
          guard let self else { throw GalaxySSIHealthRecords.Failure.unavailable }
          return try self.execute(invocation)
        }
        if Thread.isMainThread { return try MainActor.assumeIsolated { try execute() } }
        return try DispatchQueue.main.sync { try execute() }
      }))
    }
    return registry
  }

  func execute(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    try invocation.checkpoint()
    guard currentDestination() != nil else { cancellation.cancel(); throw CancellationError() }
    guard let call = pending,
          call.toolId == invocation.descriptor.id, call.arguments == invocation.input,
          invocation.context.attributes["tool_call_id"] == call.callId,
          invocation.context.sessionId == approval.threadID.uuidString,
          invocation.context.conversationId == conversationID, invocation.context.turnId == approval.id.uuidString,
          invocation.context.callerId == Self.caller, invocation.context.collaborationOwner == nil,
          invocation.context.attributes["workspace_id"] == workspaceID,
          invocation.context.attributes["task_id"] == workspaceID
    else { throw GalaxySSIHealthRecords.Failure.permission }
    try records.validateLocalCareDiscussionTurn(approval)
    guard let saved = try records.savedCareDiscussionRound(approval), saved.phase == .received,
          let bytes = saved.response else { throw GalaxySSIHealthRecords.Failure.stale }
    if Self.terminalTools.contains(call.toolId) {
      try records.retainLocalCareDiscussionResponse(approval, response: bytes)
      switch call.toolId {
      case GalaxySSIHealthCarePlan.tool:
        try records.saveLocalCarePlan(approval, arguments: call.arguments)
      case GalaxySSIHealthCareQuestions.tool:
        try records.saveLocalCareQuestionProposals(approval, arguments: call.arguments)
      case GalaxySSIHealthCareAnswerDraft.tool:
        _ = try records.stageLocalCareAnswerDraft(approval, arguments: call.arguments)
      default: throw GalaxySSIHealthRecords.Failure.permission
      }
      pending = nil
      return .success(output: ["stored": .bool(true), "requires_user_review": .bool(true),
        "executed": .bool(false), "scheduled": .bool(false)])
    }
    let wireCall = try GalaxySSIHealthCareHistoryTool.call(bytes, style: style, proposesPlan: approval.proposesPlan,
      allowsQuestionRead: approval.questions != nil, asksQuestions: approval.asksQuestions,
      allowsFeedbackRead: approval.feedbackCursor != nil)
    guard let wireCall, wireCall.name == call.toolId, wireCall.arguments == call.arguments else {
      throw GalaxySSIHealthRecords.Failure.permission
    }
    var next = saved
    let output: AgentMcpJSONObject
    if call.toolId == GalaxySSIHealthCareFeedbackTool.function {
      guard next.feedbackRemaining > 0, let cursor = next.feedbackCursor, cursor.arguments == call.arguments else {
        throw GalaxySSIHealthRecords.Failure.permission
      }
      next.feedbackRemaining -= 1
      let page = try records.readLocalCareDiscussionFeedback(approval, cursor: cursor, remaining: next.feedbackRemaining)
      next.feedbackCursor = page.cursor
      output = page.payload
    } else if call.toolId == GalaxySSIHealthCareQuestions.readTool {
      guard next.questionRemaining > 0, let cursor = next.questionCursor,
            cursor.arguments(turn: approval.id) == call.arguments else { throw GalaxySSIHealthRecords.Failure.permission }
      next.questionRemaining -= 1
      let page = try records.readLocalCareDiscussionQuestions(approval, after: cursor.after)
      next.questionCursor = .init(page, remaining: next.questionRemaining)
      output = GalaxySSIHealthCareQuestions.Cursor.payload(page, cursor: next.questionCursor, turn: approval.id)
    } else {
      guard call.toolId == GalaxySSIHealthCareHistoryTool.function, next.historyRemaining > 0 else {
        throw GalaxySSIHealthRecords.Failure.permission
      }
      next.historyRemaining -= 1
      let page: GalaxySSIHealthCareHistoryTool.Output
      if let prior = next.history, prior.authorizes(call.arguments, turn: approval.id), let cursor = prior.cursor {
        page = try GalaxySSIHealthCareHistoryTool.output(records.readLocalCareDiscussionHistory(approval, after: cursor),
          metric: approval.metric, turn: approval.id, remaining: next.historyRemaining)
        next.history = page
      } else if let (metric, _) = next.relatedEntries.first(where: { $0.value.entryArguments(turn: approval.id) == call.arguments }),
                let selected = GalaxySSIHealthMetric(rawValue: metric) {
        page = try GalaxySSIHealthCareHistoryTool.output(records.readRelatedLocalCareHistory(approval, metric: selected),
          metric: selected, turn: approval.id, remaining: next.historyRemaining)
        next.relatedEntries.removeValue(forKey: metric)
        next.relatedHistory[metric] = page
      } else if let (metric, prior) = next.relatedHistory.first(where: { $0.value.authorizes(call.arguments, turn: approval.id) }),
                let selected = GalaxySSIHealthMetric(rawValue: metric), let cursor = prior.cursor {
        page = try GalaxySSIHealthCareHistoryTool.output(records.readRelatedLocalCareHistory(approval, metric: selected, after: cursor),
          metric: selected, turn: approval.id, remaining: next.historyRemaining)
        next.relatedHistory[metric] = page
      } else { throw GalaxySSIHealthRecords.Failure.permission }
      output = page.payload
    }
    let priorRequest = try saved.request(using: template, approval: approval)
    let request = try GalaxySSIHealthCareHistoryTool.continuing(priorRequest, with: wireCall, payload: output, style: style,
      proposesPlan: approval.proposesPlan,
      historyAvailable: next.historyRemaining > 0 && (next.history?.cursor != nil || !next.relatedEntries.isEmpty || next.relatedHistory.values.contains { $0.cursor != nil }),
      allowsMaintenance: approval.history != nil, questionsAvailable: next.questionCursor != nil,
      asksQuestions: approval.asksQuestions, feedbackAvailable: next.feedbackCursor != nil)
    guard let body = request.httpBody else { throw GalaxySSIHealthRecords.Failure.invalid }
    next.index += 1
    next.phase = .prepared
    next.response = nil
    next.requestBody = body
    try records.prepareNextCareDiscussionRound(approval, expected: saved, next: next)
    pending = nil
    return .success(output: output, message: "Approved Health scope read retained.")
  }

  static let terminalTools: Set<String> = [GalaxySSIHealthCarePlan.tool,
    GalaxySSIHealthCareQuestions.tool, GalaxySSIHealthCareAnswerDraft.tool]

  private static func descriptors(_ request: URLRequest, style: GalaxySSICloudAPIStyle,
      approval: GalaxySSIHealthCareDiscussion.Approval) throws -> [AgentNativeToolDescriptor] {
    guard let body = request.httpBody,
          let root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw GalaxySSIHealthRecords.Failure.invalid }
    let functions: [[String: Any]]
    switch style {
    case .openAICompatible:
      functions = (root["tools"] as? [[String: Any]] ?? []).compactMap { $0["function"] as? [String: Any] }
    case .anthropic:
      functions = root["tools"] as? [[String: Any]] ?? []
    case .gemini:
      functions = (root["tools"] as? [[String: Any]] ?? []).flatMap { $0["functionDeclarations"] as? [[String: Any]] ?? [] }
    }
    var allowed: Set<String> = []
    if approval.hasHistoryReads { allowed.insert(GalaxySSIHealthCareHistoryTool.function) }
    if approval.questionCursor != nil { allowed.insert(GalaxySSIHealthCareQuestions.readTool) }
    if approval.feedbackCursor != nil { allowed.insert(GalaxySSIHealthCareFeedbackTool.function) }
    if approval.proposesPlan { allowed.insert(GalaxySSIHealthCarePlan.tool) }
    if approval.asksQuestions { allowed.insert(GalaxySSIHealthCareQuestions.tool) }
    if approval.allowsAnswerDraft { allowed.insert(GalaxySSIHealthCareAnswerDraft.tool) }
    var ids = Set<String>()
    return try functions.map { function in
      guard let name = function["name"] as? String, allowed.contains(name), ids.insert(name).inserted,
            let description = function["description"] as? String,
            let schema = (function["parameters"] ?? function["input_schema"] ?? function["parametersJsonSchema"]) as? [String: Any]
      else { throw GalaxySSIHealthRecords.Failure.permission }
      let input = try JSONDecoder().decode(AgentMcpJSONObject.self, from: JSONSerialization.data(withJSONObject: schema))
      return try AgentNativeToolDescriptor(id: name, version: "1.0.0", title: name, description: description,
        location: .phone, inputSchema: input, risk: terminalTools.contains(name) ? .medium : .low,
        requiredConsents: [.init(id: approval.carePermission.uuidString), .init(id: approval.onlinePermission.uuidString)],
        idempotency: terminalTools.contains(name) ? .idempotencyKeyRequired : .idempotent,
        effect: terminalTools.contains(name) ? .mutation : .readOnly)
    }
  }
}
