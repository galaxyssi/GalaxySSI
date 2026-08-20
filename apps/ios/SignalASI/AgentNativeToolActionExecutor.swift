import Foundation

struct AgentNativeToolActionExecutor: AgentActionExecutor {
  var registry: AgentNativeToolRegistry
  var delegate: AgentActionExecutor
  var nowMillis: () -> Int64
  var workspaceIdProvider: (AgentAction, AgentScreenContext) -> String
  var eventSink: AgentNativeToolLifecycleEventSink
  var maxRetries: Int

  init(
    registry: AgentNativeToolRegistry,
    delegate: AgentActionExecutor,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    workspaceIdProvider: @escaping (AgentAction, AgentScreenContext) -> String = { action, _ in
      AgentNativeToolActionExecutor.defaultWorkspaceId(for: action)
    },
    eventSink: AgentNativeToolLifecycleEventSink = .none,
    maxRetries: Int = 1
  ) {
    self.registry = registry
    self.delegate = delegate
    self.nowMillis = nowMillis
    self.workspaceIdProvider = workspaceIdProvider
    self.eventSink = eventSink
    self.maxRetries = max(0, maxRetries)
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    guard action.kind == .callNativeTool else {
      return delegate.execute(action: action, screen: screen)
    }
    let toolId = Self.clean(action.parameters["tool_id"] ?? "")
    guard !toolId.isEmpty else {
      return Self.failure(action, "Native tool id is missing.", code: "missing_tool_id")
    }
    guard let definition = registry.lookup(toolId) else {
      return Self.failure(action, "Native tool is not registered: \(toolId)", code: "unknown_tool")
    }
    let input: AgentMcpJSONObject
    switch Self.parseInput(action.parameters["input_json"] ?? "") {
    case .success(let parsed):
      input = parsed
    case .failure(let message):
      return Self.failure(action, message, code: "invalid_input_json", toolId: toolId)
    }

    let workspaceId = Self.clean(workspaceIdProvider(action, screen))
    let scopedInput = Self.bindWorkspaceInput(toolId: toolId, input: input, workspaceId: workspaceId)
    let descriptor = definition.descriptor
    let requestedVersion = Self.clean(action.parameters["tool_version"] ?? "")
    guard requestedVersion.isEmpty || requestedVersion == descriptor.version else {
      return Self.failure(
        action,
        "The proposed tool version does not match the phone manifest.",
        code: "tool_version_mismatch",
        toolId: toolId
      )
    }
    let idempotencyKey = Self.idempotencyKey(for: action, descriptor: descriptor)
    let baseInvocationId = Self.clean(action.parameters["invocation_id"] ?? "").nilIfEmpty ?? action.id
    let deadlineEpochMillis = Self.deadlineEpochMillis(action: action, nowMillis: nowMillis())
    let maximumAttempts = descriptor.idempotency == .nonIdempotent ? 1 : maxRetries + 1
    var attempt = 0
    var result: AgentNativeToolResult

    repeat {
      attempt += 1
      let context = AgentNativeToolInvocationContext(
        invocationId: Self.invocationId(base: baseInvocationId, attempt: attempt),
        sessionId: Self.clean(action.parameters[Self.sessionIdKey] ?? ""),
        conversationId: Self.clean(action.parameters[Self.conversationIdKey] ?? ""),
        turnId: Self.clean(action.parameters[Self.turnIdKey] ?? ""),
        callerId: "signalasi.mobile_agent.plan",
        requestedAtEpochMillis: nowMillis(),
        deadlineEpochMillis: deadlineEpochMillis,
        idempotencyKey: idempotencyKey,
        grantedPermissions: Set(descriptor.requiredPermissions.filter(\.required).map(\.id)),
        grantedConsents: Set(descriptor.requiredConsents.filter(\.required).map(\.id)),
        attributes: Self.attributes(
          action: action,
          screen: screen,
          workspaceId: workspaceId,
          explicitUserApproval: action.requiresConfirmation,
          retryAttempt: attempt - 1
        )
      )
      result = registry.invoke(
        toolId,
        input: scopedInput,
        context: context,
        hooks: Self.lifecycleHooks(
          toolId: toolId,
          context: context,
          nowMillis: nowMillis,
          eventSink: eventSink
        )
      )
      guard !result.isSuccess,
            result.error?.retryable == true,
            attempt < maximumAttempts else {
        break
      }
    } while true

    return Self.actionResult(action: action, result: result, retryCount: attempt - 1)
  }

  static func defaultWorkspaceId(for action: AgentAction) -> String {
    let explicit = clean(action.parameters[workspaceIdKey] ?? "")
    if !explicit.isEmpty {
      return explicit
    }
    return AgentWorkspaceScope.id(
      conversationId: clean(action.parameters[conversationIdKey] ?? ""),
      sessionId: clean(action.parameters[sessionIdKey] ?? "")
    )
  }

  private static func parseInput(_ raw: String) -> InputParseResult {
    let source = clean(raw).isEmpty ? "{}" : raw
    guard let data = source.data(using: .utf8) else {
      return .failure("Native tool input is not UTF-8 JSON.")
    }
    do {
      let value = try JSONDecoder().decode(AgentMcpJSONValue.self, from: data)
      guard case .object(let object) = value else {
        return .failure("Native tool input must be a JSON object.")
      }
      return .success(object)
    } catch {
      return .failure("Native tool input is not valid JSON.")
    }
  }

  private static func bindWorkspaceInput(
    toolId: String,
    input: AgentMcpJSONObject,
    workspaceId: String
  ) -> AgentMcpJSONObject {
    guard toolId.hasPrefix(workspaceToolPrefix), !workspaceId.isEmpty else {
      return input
    }
    var output = input
    output["workspace_id"] = .string(workspaceId)
    return output
  }

  private static func idempotencyKey(
    for action: AgentAction,
    descriptor: AgentNativeToolDescriptor
  ) -> String? {
    let explicit = clean(action.parameters["idempotency_key"] ?? "")
    if !explicit.isEmpty {
      return explicit
    }
    switch descriptor.idempotency {
    case .idempotent, .idempotencyKeyRequired:
      return action.id
    case .nonIdempotent:
      return nil
    }
  }

  private static func invocationId(base: String, attempt: Int) -> String {
    guard attempt > 1 else { return base }
    let suffix = "-retry-\(attempt - 1)"
    return String(base.prefix(max(1, 160 - suffix.count))) + suffix
  }

  private static func deadlineEpochMillis(action: AgentAction, nowMillis: Int64) -> Int64? {
    let seconds = Int64(clean(action.parameters["tool_timeout_seconds"] ?? "")) ?? 0
    guard seconds > 0 else { return nil }
    return nowMillis + min(seconds, 600) * 1_000
  }

  private static func attributes(
    action: AgentAction,
    screen: AgentScreenContext,
    workspaceId: String,
    explicitUserApproval: Bool,
    retryAttempt: Int = 0
  ) -> [String: String] {
    [
      "execution_authority": "signalasi-phone",
      "confirmation_id": action.id,
      "step_id": action.id,
      "workspace_id": workspaceId,
      "explicit_user_approval": explicitUserApproval.description,
      "retry_attempt": String(max(0, retryAttempt)),
      "foreground_app": screen.foregroundApp,
      "page_title": screen.pageTitle,
      "contact_id": clean(action.parameters["_signalasi_contact_id"] ?? ""),
      "response_language": clean(action.parameters["response_language"] ?? ""),
      AgentNativeToolRegistry.legacyActionIdAttribute: action.id
    ]
  }

  private static func lifecycleHooks(
    toolId: String,
    context: AgentNativeToolInvocationContext,
    nowMillis: @escaping () -> Int64,
    eventSink: AgentNativeToolLifecycleEventSink
  ) -> AgentNativeToolInvocationHooks {
    AgentNativeToolInvocationHooks(
      nowMillis: nowMillis,
      onStarted: { invocation in
        eventSink.emit(event(
          stage: .started,
          toolId: toolId,
          context: context,
          invocationId: invocation.context.invocationId,
          timestampMillis: invocation.startedAtEpochMillis
        ))
      },
      onProgress: { invocation, progress in
        eventSink.emit(event(
          stage: .progress,
          toolId: toolId,
          context: context,
          invocationId: invocation.context.invocationId,
          progressStage: progress.stage,
          message: progress.message,
          percent: progress.percent,
          sequence: progress.sequence,
          timestampMillis: progress.timestampEpochMillis
        ))
      },
      onFinished: { result in
        eventSink.emit(event(
          stage: .finished,
          toolId: toolId,
          context: context,
          invocationId: result.receipt.invocationId,
          status: result.status,
          message: result.message.nilIfEmpty ?? result.error?.message ?? "",
          timestampMillis: result.receipt.finishedAtEpochMillis
        ))
      }
    )
  }

  private static func event(
    stage: AgentNativeToolLifecycleStage,
    toolId: String,
    context: AgentNativeToolInvocationContext,
    invocationId: String,
    status: AgentNativeToolResultStatus? = nil,
    progressStage: String = "",
    message: String = "",
    percent: Int? = nil,
    sequence: Int64 = 0,
    timestampMillis: Int64
  ) -> AgentNativeToolLifecycleEvent {
    AgentNativeToolLifecycleEvent(
      stage: stage,
      toolId: toolId,
      invocationId: invocationId,
      stepId: (context.attributes["step_id"] ?? "").nilIfEmpty ?? invocationId,
      conversationId: context.conversationId,
      turnId: context.turnId,
      status: status,
      progressStage: progressStage,
      message: message,
      percent: percent,
      sequence: sequence,
      timestampMillis: timestampMillis
    )
  }

  private static func actionResult(
    action: AgentAction,
    result: AgentNativeToolResult,
    retryCount: Int = 0
  ) -> AgentActionResult {
    let output = String(AgentMcpJSONCodec.stringify(result.output).prefix(maxOutputCharacters))
    let nativeMessage = modelVisibleMessage(result)
    return AgentActionResult(
      actionId: action.id,
      success: result.isSuccess,
      message: nativeMessage.nilIfEmpty ?? output,
      metadata: [
        "native_tool_id": result.provenance.toolId,
        "native_tool_version": result.provenance.toolVersion,
        "native_tool_status": result.status.rawValue,
        "native_tool_output": output,
        "native_receipt_id": result.receipt.invocationId,
        "invocation_id": result.receipt.invocationId,
        "idempotency_key": result.receipt.idempotencyKey ?? "",
        "started_at_millis": String(result.receipt.startedAtEpochMillis),
        "completed_at_millis": String(result.receipt.finishedAtEpochMillis),
        "native_retry_count": String(max(0, retryCount)),
        "native_attempt_count": String(max(1, retryCount + 1)),
        "provenance": result.provenance.executorId
      ]
    )
  }

  private static func modelVisibleMessage(_ result: AgentNativeToolResult) -> String {
    let base = clean(result.message).nilIfEmpty ?? clean(result.error?.message ?? "")
    guard !result.isSuccess, let error = result.error else { return base }

    var seen = Set<String>()
    let issues = ["issues", "validation_issues"]
      .flatMap { error.details[$0]?.arrayValue ?? [] }
      .compactMap { value -> String? in
        guard let issue = value.objectValue else { return nil }
        let summary = [
          clean(issue["path"]?.stringValue ?? ""),
          clean(issue["code"]?.stringValue ?? ""),
          clean(issue["message"]?.stringValue ?? "")
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " | ")
        return summary.isEmpty || !seen.insert(summary).inserted ? nil : summary
      }
      .prefix(maxVisibleIssues)

    guard !issues.isEmpty else { return base }
    let suffix = issues.joined(separator: "; ")
    let message = base.isEmpty ? suffix : "\(base): \(suffix)"
    return String(message.prefix(maxOutputCharacters))
  }

  private static func failure(
    _ action: AgentAction,
    _ message: String,
    code: String,
    toolId: String = ""
  ) -> AgentActionResult {
    AgentActionResult(
      actionId: action.id,
      success: false,
      message: message,
      metadata: [
        "native_tool_id": toolId,
        "native_tool_status": "rejected",
        "error_code": code
      ]
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let conversationIdKey = "_signalasi_conversation_id"
  private static let turnIdKey = "_signalasi_turn_id"
  private static let sessionIdKey = "_signalasi_session_id"
  private static let workspaceIdKey = "_signalasi_workspace_id"
  private static let workspaceToolPrefix = "signalasi.workspace."
  private static let maxOutputCharacters = 8_000
  private static let maxVisibleIssues = 8

  private enum InputParseResult {
    case success(AgentMcpJSONObject)
    case failure(String)
  }
}
