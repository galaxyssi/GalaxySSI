import Foundation

enum AgentConversationScheduleTools {
  static let list = "galaxyssi.schedules.list"
  static let manage = "galaxyssi.schedules.manage"
  static let ids: Set<String> = [list, manage]
  private static let contract =
    "Decide recurring-task intent from the full conversation, not words such as daily or every day in questions or habits. " +
    "Only use this phone-owned tool when the user asks for future repeated work; clarify genuine ambiguity. " +
    "List this conversation's tasks and timezone before changing one. Use its exact ID and observed revision. " +
    "Create and update request an immediate occurrence and then repeat. A saved receipt is not evidence that the action ran. " +
    "During an occurrence do the assigned work, never create or change a schedule."

  static func executables(
    invoke: @escaping (String, AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
  ) throws -> [AgentNativeToolExecutableDefinition] {
    try [list, manage].map { id in
      let writes = id == manage
      let descriptor = try AgentNativeToolDescriptor(
        id: id, version: AgentPhoneNativeToolCatalog.version,
        title: writes ? "Manage this conversation's recurring tasks" : "List this conversation's recurring tasks",
        description: writes ? contract : "Read this conversation's exact schedule IDs, revisions and phone timezone.",
        location: .application, inputSchema: writes ? manageSchema : schema([:]),
        outputSchema: AgentNativeToolDescriptor.objectSchema(), risk: writes ? .medium : .low,
        capabilities: ["task_execution"], timeoutMillis: 15_000,
        idempotency: writes ? .idempotencyKeyRequired : .idempotent,
        effect: writes ? .mutation : .readOnly
      )
      return AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "ios.conversation_schedule"),
        executor: { invocation in
          try invocation.checkpoint()
          return invoke(id, invocation)
        })
    }
  }

  enum Operation: String, CaseIterable { case create, update, pause, resume }

  @MainActor
  static func execute(_ tool: String, context: AgentNativeToolInvocationContext, input: AgentMcpJSONObject,
                      store: GalaxySSIStore,
                      changed: (AgentProactiveTask, Operation, ChatMessage) -> Void) -> AgentNativeToolExecutionResult {
    let conversation = context.conversationId
    guard !conversation.isBlank, let session = store.agentSession(id: conversation), session.status == .active,
          !session.privateMode, !session.trackingPaused, session.mergedIntoConversationId.isBlank,
          session.collaborationRoster == nil else {
      return failure("schedule_context_missing", "An active conversation that allows scheduled tasks is required.")
    }
    let zone = TimeZone.current.identifier
    if tool == list, input.isEmpty {
      return .success(output: ["time_zone": .string(zone),
        "tasks": .array(store.conversationSchedules(conversation).map(value))], message: "Read saved schedules.")
    }
    guard tool == manage, !context.turnId.isBlank,
          !conversation.hasPrefix("proactive:"), (context.attributes["proactive_task_id"] ?? "").isBlank,
          !store.proactiveRuns.contains(where: { $0.runId == context.turnId }),
          let source = store.agentSessionMessages(conversation).last(where: {
            $0.isMine && !$0.isSystem && $0.turnId.ifBlank($0.id.uuidString) == context.turnId
          }), !source.readOnlyAnalysis,
          !source.deliveryTrace.contains(where: { $0.stage == AgentConversationSchedule.occurrenceStage }) else {
      return failure("schedule_turn_unavailable", "Use an originating user turn, not a scheduled occurrence.")
    }
    let request: Request
    do { request = try Request(input, timeZone: zone) }
    catch { return failure("invalid_schedule_arguments", error.localizedDescription) }
    do {
      let saved: AgentProactiveTask
      var previous: AgentProactiveTask?
      if let id = request.taskID {
        guard let current = store.automationTask(id: id), current.action.isConversationSchedule,
              current.action.conversationId == conversation else {
          return failure("schedule_not_found", "List this conversation's tasks and use an observed task ID.")
        }
        guard current.revision == request.revision else {
          return failure("schedule_revision_conflict", "The task changed. List its current state before editing.")
        }
        previous = current
      }
      var created = false
      switch request.operation {
      case .create:
        let creationID = AgentTaskIdentityPolicy.taskId(ownerId: store.profile.identityFingerprint, contactId: manage,
          sourceMessageId: AgentMcpJSONCodec.sha256(input), conversationId: conversation, turnId: context.turnId)
        created = store.automationTask(id: creationID) == nil
        saved = try store.saveConversationSchedule(conversationId: conversation, id: nil, prompt: request.prompt ?? "",
          trigger: request.trigger, frequency: request.label ?? "", creationId: creationID)
      case .update:
        saved = try store.saveConversationSchedule(conversationId: conversation, id: request.taskID,
          prompt: request.prompt ?? "", trigger: request.trigger, frequency: request.label ?? "")
      case .pause, .resume:
        guard let id = request.taskID, try store.setConversationScheduleEnabled(id: id, conversationId: conversation,
          enabled: request.operation == .resume), let updated = store.automationTask(id: id) else {
          return failure("schedule_save_failed", "The schedule could not be updated.")
        }
        saved = updated
      }
      if created || (previous != nil && previous?.revision != saved.revision) { changed(saved, request.operation, source) }
      return .success(output: ["task": value(saved), "schedule_saved": .bool(true), "execution_verified": .bool(false)],
        message: "Schedule saved. Occurrence execution is reported separately.")
    } catch {
      return failure("schedule_save_failed", "The schedule could not be saved.")
    }
  }

  private static func failure(_ code: String, _ message: String) -> AgentNativeToolExecutionResult {
    .failure(code: code, message: message, details: ["schedule_changed": .bool(false)])
  }

  struct Request {
    let operation: Operation
    let taskID: String?
    let revision: Int?
    let prompt: String?
    let label: String?
    let trigger: AgentProactiveTrigger?

    init(_ input: AgentMcpJSONObject, timeZone: String) throws {
      guard let name = input["operation"]?.strictStringValue, let operation = Operation(rawValue: name),
            Set(input.keys).isSubset(of: ["operation", "task_id", "expected_revision", "prompt", "schedule_label", "schedule"])
      else { throw AgentProactiveTaskError.invalid("Unknown schedule operation or argument.") }
      self.operation = operation
      taskID = try Self.text(input, "task_id", limit: 128)
      let observedRevision = try Self.positiveInteger(input, "expected_revision")
      guard (observedRevision ?? 0) <= Int64(Int32.max) else {
        throw AgentProactiveTaskError.invalid("Invalid observed schedule revision.")
      }
      revision = observedRevision.flatMap { Int(exactly: $0) }
      prompt = try Self.text(input, "prompt", limit: 4_096)
      label = try Self.text(input, "schedule_label", limit: 200)
      if let raw = input["schedule"] {
        guard let fields = raw.objectValue,
              Set(fields.keys).isSubset(of: ["kind", "interval_seconds", "cron", "time_zone"]) else {
          throw AgentProactiveTaskError.invalid("A structured interval or cron is required.")
        }
        let zone = try Self.text(fields, "time_zone", limit: 100) ?? timeZone
        switch fields["kind"]?.strictStringValue {
        case "interval" where fields["cron"] == nil:
          guard let seconds = try Self.positiveInteger(fields, "interval_seconds") else {
            throw AgentProactiveTaskError.invalid("An interval in whole seconds is required.")
          }
          trigger = try AgentProactiveTrigger(kind: .interval, timeZone: zone, intervalSeconds: seconds)
        case "cron" where fields["interval_seconds"] == nil:
          guard let cron = try Self.text(fields, "cron", limit: 128) else {
            throw AgentProactiveTaskError.invalid("A five-field cron expression is required.")
          }
          trigger = try AgentProactiveTrigger(kind: .cron, cron: cron, timeZone: zone)
        default: throw AgentProactiveTaskError.invalid("Choose either an interval or a cron expression.")
        }
      } else { trigger = nil }
      let valid: Bool
      switch operation {
      case .create: valid = taskID == nil && revision == nil && prompt != nil && label != nil && trigger != nil
      case .update:
        valid = taskID != nil && revision != nil && (prompt != nil || trigger != nil) && ((label == nil) == (trigger == nil))
      case .pause, .resume: valid = taskID != nil && revision != nil && prompt == nil && label == nil && trigger == nil
      }
      guard valid else { throw AgentProactiveTaskError.invalid("Supply the arguments required by the schedule operation.") }
    }

    private static func text(_ input: AgentMcpJSONObject, _ key: String, limit: Int) throws -> String? {
      guard let field = input[key] else { return nil }
      guard let text = field.strictStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty, text.count <= limit else {
        throw AgentProactiveTaskError.invalid("Invalid schedule field: \(key).")
      }
      return text
    }

    private static func positiveInteger(_ input: AgentMcpJSONObject, _ key: String) throws -> Int64? {
      guard let field = input[key] else { return nil }
      switch field {
      case .int(let value) where value > 0: return value
      case .double(let value) where value > 0:
        if let integer = Int64(exactly: value) { return integer }
      default: break
      }
      throw AgentProactiveTaskError.invalid("A positive whole number is required for \(key).")
    }
  }

  static func value(_ task: AgentProactiveTask) -> AgentMcpJSONValue {
    let trigger = task.trigger
    var schedule: AgentMcpJSONObject = ["kind": .string(trigger.kind.rawValue), "time_zone": .string(trigger.timeZone)]
    if trigger.kind == .cron { schedule["cron"] = .string(trigger.cron) }
    if trigger.kind == .interval { schedule["interval_seconds"] = .int(trigger.intervalSeconds) }
    return .object(["task_id": .string(task.taskId), "revision": .int(Int64(task.revision)),
      "enabled": .bool(task.enabled), "prompt": .string(task.action.prompt), "schedule_label": .string(task.action.scheduleText),
      "schedule": .object(schedule), "next_run_at_millis": .int(task.nextRunAtMillis), "last_status": .string(task.lastStatus.rawValue)])
  }

  private static func schema(_ properties: AgentMcpJSONObject, required: [String] = []) -> AgentMcpJSONObject {
    ["type": .string("object"), "properties": .object(properties),
     "required": .array(required.map(AgentMcpJSONValue.string)), "additionalProperties": .bool(false)]
  }

  private static func text(_ maximum: Int64) -> AgentMcpJSONValue {
    .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(maximum)])
  }

  private static func choices(_ values: [String]) -> AgentMcpJSONValue {
    .object(["type": .string("string"), "enum": .array(values.map(AgentMcpJSONValue.string))])
  }

  private static let manageSchema = schema([
    "operation": choices(Operation.allCases.map(\.rawValue)), "task_id": text(128),
    "expected_revision": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(Int64(Int32.max))]),
    "prompt": text(4_096), "schedule_label": text(200),
    "schedule": .object(schema(["kind": choices(["interval", "cron"]), "cron": text(128), "time_zone": text(100),
      "interval_seconds": .object(["type": .string("integer"), "minimum": .int(AgentProactiveTrigger.minIntervalSeconds),
        "maximum": .int(AgentProactiveTrigger.maxIntervalSeconds)])], required: ["kind"]))
  ], required: ["operation"])
}
