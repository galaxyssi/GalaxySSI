import Foundation

enum AgentScheduleFollowupPolicy {
  static let receiptStage = "local_workflow_schedule_receipt"

  static func receiptId(turnId: String) -> String { "schedule-command:" + turnId }

  static func target(before outgoing: ChatMessage, messages: [ChatMessage], liveTaskIds: Set<String>) -> String? {
    guard let prior = AgentOwnedOperationContext.previousRequest(before: outgoing, in: messages),
          let index = messages.firstIndex(where: { $0.id == outgoing.id }),
          let sourceIndex = messages[..<index].firstIndex(where: { $0.id == prior.id }) else { return nil }
    let turn = prior.turnId.ifBlank(prior.id.uuidString)
    let ids = Set(messages[(sourceIndex + 1)..<index].compactMap { reply -> String? in
      guard !reply.isMine, !reply.isSystem, reply.conversationId == prior.conversationId,
            reply.contactId == prior.contactId, reply.sourceConversationId.isBlank, reply.turnId == turn,
            [.delivered, .read].contains(reply.deliveryStatus),
            reply.remoteMessageId == receiptId(turnId: turn),
            let receipt = reply.deliveryTrace.first, receipt.stage == receiptStage,
            prior.deliveryTrace.contains(where: { $0.stage == receiptStage && $0.detail == receipt.detail }),
            liveTaskIds.contains(receipt.detail) else { return nil }
      return receipt.detail
    })
    return ids.count == 1 ? ids.first : nil
  }
}

@MainActor
enum AgentWorkflowRunScheduleCommandRouter {
  struct Result {
    let text: String
    let actionId: String
    let workflowToRun: AgentWorkflow?
    var scheduleTaskId: String? = nil
  }

  private enum ScheduleKind {
    case daily(hour: Int, minute: Int)
    case interval(minutes: Int)
  }

  private struct ScheduleRequest {
    let workflowReference: String
    let kind: ScheduleKind
  }

  static func handle(
    _ input: String,
    store: GalaxySSIStore,
    workflowStore: AgentWorkflowStore = UserDefaultsAgentWorkflowStore.shared,
    scopedTaskId: () -> String? = { nil }
  ) -> Result? {
    let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = command.lowercased()
    guard !command.isEmpty else { return nil }

    if let reference = prefixedValue(command, prefixes: ["run workflow ", "start workflow "]) {
      guard let workflow = workflowStore.find(reference) else {
        return result("Workflow '\(reference)' was not found", actionId: "workflow_run")
      }
      return Result(
        text: "Starting workflow \(workflow.name)",
        actionId: "workflow_run",
        workflowToRun: workflow
      )
    }
    if let request = parseSchedule(command) {
      return schedule(request, store: store, workflowStore: workflowStore)
    }
    if isScheduleListCommand(normalized) {
      return listSchedules(store: store)
    }
    if let reference = prefixedValue(
      command,
      prefixes: ["cancel schedule ", "delete schedule ", "remove schedule "]
    ) {
      return cancelSchedule(reference, store: store, workflowStore: workflowStore)
    }
    let explicitPause = prefixedValue(command, prefixes: ["pause schedule ", "stop schedule "])
    let explicitResume = prefixedValue(command, prefixes: ["resume schedule "])
    if let reference = explicitPause ?? explicitResume {
      guard let task = namedSchedule(reference, store: store, workflowStore: workflowStore) else {
        return result("Name a single workflow schedule to update.", actionId: "workflow_schedule_control")
      }
      return setEnabled(explicitResume != nil, task: task, store: store)
    }
    let control = normalized.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    let pause = ["stop", "pause", "cancel", "pause schedule", "stop schedule",
      "\u{505c}\u{6b62}", "\u{6682}\u{505c}", "\u{53d6}\u{6d88}"].contains(control)
    let resume = ["resume", "continue", "resume schedule", "\u{7ee7}\u{7eed}", "\u{6062}\u{590d}"].contains(control)
    let change = prefixedValue(command, prefixes: ["change to ", "update it to ", "change schedule to ", "\u{6539}\u{6210}", "\u{6539}\u{4e3a}"])
    if pause || resume || change != nil {
      guard let id = scopedTaskId(), let task = store.automationTask(id: id),
            task.action.kind == .workflow, isSchedule(task) else { return nil }
      if let change { return update(change, task: task, store: store) }
      return setEnabled(resume, task: task, store: store)
    }
    if isManagementCommand(normalized) {
      return result(
        "Workflow execution commands: run workflow Name; schedule workflow Name at HH:mm; schedule workflow Name every 30 minutes; list schedules; cancel schedule Name.",
        actionId: "workflow_execution_syntax"
      )
    }
    return nil
  }

  private static func parseSchedule(_ command: String) -> ScheduleRequest? {
    let dailyPattern = #"^(?:schedule workflow|schedule)\s+(.+?)\s+at\s+(\d{1,2}):(\d{2})$"#
    if let captures = captures(dailyPattern, in: command), captures.count == 3,
       let hour = Int(captures[1]), let minute = Int(captures[2]),
       (0...23).contains(hour), (0...59).contains(minute) {
      return ScheduleRequest(
        workflowReference: captures[0].trimmingCharacters(in: .whitespacesAndNewlines),
        kind: .daily(hour: hour, minute: minute)
      )
    }

    let intervalPattern = #"^(?:schedule workflow|schedule)\s+(.+?)\s+every\s+(\d+)\s+(minutes?|hours?|days?)$"#
    guard let values = captures(intervalPattern, in: command), values.count == 3,
          let amount = Int64(values[1]) else { return nil }
    let unit = values[2].lowercased()
    let multiplier: Int64
    if unit.hasPrefix("day") {
      multiplier = 24 * 60
    } else if unit.hasPrefix("hour") {
      multiplier = 60
    } else {
      multiplier = 1
    }
    let rawMinutes = amount.multipliedReportingOverflow(by: multiplier)
    guard !rawMinutes.overflow, rawMinutes.partialValue <= Int64(Int.max) else { return nil }
    let minutes = Int(rawMinutes.partialValue)
    guard !values[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return ScheduleRequest(
      workflowReference: values[0].trimmingCharacters(in: .whitespacesAndNewlines),
      kind: .interval(minutes: minutes)
    )
  }

  private static func schedule(
    _ request: ScheduleRequest,
    store: GalaxySSIStore,
    workflowStore: AgentWorkflowStore
  ) -> Result {
    guard let workflow = workflowStore.find(request.workflowReference) else {
      return result("Workflow '\(request.workflowReference)' was not found", actionId: "workflow_schedule")
    }
    let existing = store.automationTasks().first {
      $0.action.kind == .workflow && $0.action.targetId == workflow.id && isSchedule($0)
    }
    do {
      let timeZone = TimeZone.autoupdatingCurrent.identifier
      let trigger: AgentProactiveTrigger
      let label: String
      switch request.kind {
      case .daily(let hour, let minute):
        trigger = try AgentProactiveTrigger(
          kind: .cron,
          cron: "\(minute) \(hour) * * *",
          timeZone: timeZone
        )
        label = String(format: "daily at %02d:%02d", hour, minute)
      case .interval(let minutes):
        guard (15...7 * 24 * 60).contains(minutes) else {
          return result(
            "Workflow interval must be between 15 minutes and 7 days",
            actionId: "workflow_schedule"
          )
        }
        trigger = try AgentProactiveTrigger(
          kind: .interval,
          timeZone: timeZone,
          intervalSeconds: Int64(minutes) * 60
        )
        label = "every \(minutes) minutes"
      }
      let now = Int64(Date().timeIntervalSince1970 * 1_000)
      let action = try AgentProactiveAction(
        kind: .workflow,
        targetId: workflow.id,
        prompt: workflow.goal
      )
      let task = try AgentProactiveTask(
        taskId: existing?.taskId ?? "ios-workflow-schedule-\(UUID().uuidString.lowercased())",
        name: "Workflow schedule: \(workflow.name)",
        trigger: trigger,
        action: action,
        policy: existing?.policy ?? AgentProactiveTask.defaultPolicy(),
        enabled: true,
        nextRunAtMillis: existing?.nextRunAtMillis ?? 0,
        lastRunAtMillis: existing?.lastRunAtMillis ?? 0,
        lastStatus: existing?.lastStatus ?? .queued,
        runCount: existing?.runCount ?? 0,
        consecutiveFailures: existing?.consecutiveFailures ?? 0,
        revision: existing?.revision ?? 1,
        createdAtMillis: existing?.createdAtMillis ?? now,
        updatedAtMillis: now
      )
      let saved = try store.saveAutomationTask(task)
      return result(
        "Scheduled \(workflow.name): \(label); next=\(timestamp(saved.nextRunAtMillis))",
        actionId: "workflow_schedule", scheduleTaskId: saved.taskId
      )
    } catch {
      return result("Workflow could not be scheduled: \(error.localizedDescription)", actionId: "workflow_schedule")
    }
  }

  private static func listSchedules(store: GalaxySSIStore) -> Result {
    let schedules = store.automationTasks().filter {
      $0.action.kind == .workflow && isSchedule($0)
    }
    guard !schedules.isEmpty else {
      return result("No workflow schedules", actionId: "workflow_schedule_list")
    }
    let lines = schedules.prefix(20).map { task in
      "- \(task.name.replacingOccurrences(of: "Workflow schedule: ", with: "")) | \(scheduleLabel(task.trigger)) | next=\(timestamp(task.nextRunAtMillis))"
    }
    return result(
      "Workflow schedules: \(schedules.count)\n\(lines.joined(separator: "\n"))",
      actionId: "workflow_schedule_list"
    )
  }

  private static func cancelSchedule(
    _ reference: String,
    store: GalaxySSIStore,
    workflowStore: AgentWorkflowStore
  ) -> Result {
    guard let task = namedSchedule(reference, store: store, workflowStore: workflowStore) else {
      return result("Schedule '\(reference)' was not found", actionId: "workflow_schedule_cancel")
    }
    guard store.deleteAutomationTask(id: task.taskId) else {
      return result("Schedule '\(reference)' was not found", actionId: "workflow_schedule_cancel")
    }
    return result("Cancelled schedule for \(reference)", actionId: "workflow_schedule_cancel")
  }

  private static func namedSchedule(
    _ reference: String, store: GalaxySSIStore, workflowStore: AgentWorkflowStore
  ) -> AgentProactiveTask? {
    let workflow = workflowStore.find(reference)
    let candidates = store.automationTasks().filter { task in
      guard task.action.kind == .workflow, isSchedule(task) else { return false }
      let name = task.name.replacingOccurrences(of: "Workflow schedule: ", with: "")
      return task.taskId == reference || workflow?.id == task.action.targetId ||
        name.caseInsensitiveCompare(reference) == .orderedSame
    }
    return candidates.count == 1 ? candidates.first : nil
  }

  private static func setEnabled(_ enabled: Bool, task: AgentProactiveTask, store: GalaxySSIStore) -> Result {
    let stage = "workflow_schedule_control"
    do {
      guard try store.setAutomationTaskEnabled(id: task.taskId, enabled: enabled) else {
        return result("The workflow schedule no longer exists.", actionId: stage)
      }
      return result(enabled ? "Resumed \(task.name)" : "Paused \(task.name)",
        actionId: stage, scheduleTaskId: task.taskId)
    } catch {
      return result("Workflow schedule could not be updated: \(error.localizedDescription)", actionId: stage)
    }
  }

  private static func update(_ change: String, task: AgentProactiveTask, store: GalaxySSIStore) -> Result {
    let stage = "workflow_schedule_update"
    var edited = task
    do {
      let lower = change.lowercased()
      if lower.hasPrefix("at ") || lower.hasPrefix("every ") {
        guard let request = parseSchedule("schedule workflow current " + change) else {
          return result("Use a valid time or recurring interval.", actionId: stage)
        }
        switch request.kind {
        case .daily(let hour, let minute):
          edited.trigger = try AgentProactiveTrigger(kind: .cron, cron: "\(minute) \(hour) * * *", timeZone: task.trigger.timeZone)
        case .interval(let minutes):
          guard (15...7 * 24 * 60).contains(minutes) else {
            return result("Workflow interval must be between 15 minutes and 7 days", actionId: stage)
          }
          edited.trigger = try AgentProactiveTrigger(kind: .interval, timeZone: task.trigger.timeZone,
            intervalSeconds: Int64(minutes) * 60)
        }
      } else {
        guard change.count <= 65_536 else {
          return result("Workflow prompt is too long.", actionId: stage)
        }
        edited.action.prompt = change
      }
      let saved = try store.saveAutomationTask(edited)
      return result("Updated \(saved.name)", actionId: stage, scheduleTaskId: saved.taskId)
    } catch {
      return result("Workflow schedule could not be updated: \(error.localizedDescription)", actionId: stage)
    }
  }

  private static func isSchedule(_ task: AgentProactiveTask) -> Bool {
    [.cron, .interval].contains(task.trigger.kind)
  }

  private static func scheduleLabel(_ trigger: AgentProactiveTrigger) -> String {
    switch trigger.kind {
    case .cron: return "daily \(trigger.cron) (\(trigger.timeZone))"
    case .interval: return "every \(trigger.intervalSeconds / 60) minutes"
    default: return trigger.kind.rawValue.lowercased()
    }
  }

  private static func isScheduleListCommand(_ normalized: String) -> Bool {
    ["schedules", "list schedules", "show schedules", "workflow schedules"].contains(normalized)
  }

  private static func isManagementCommand(_ normalized: String) -> Bool {
    [
      "run workflow",
      "start workflow",
      "schedule",
      "schedule workflow",
      "cancel schedule",
      "delete schedule",
      "remove schedule"
    ].contains { normalized == $0 || normalized.hasPrefix($0 + " ") }
  }

  private static func prefixedValue(_ value: String, prefixes: [String]) -> String? {
    let lower = value.lowercased()
    guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
    let value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  private static func result(_ text: String, actionId: String, scheduleTaskId: String? = nil) -> Result {
    Result(text: text, actionId: actionId, workflowToRun: nil, scheduleTaskId: scheduleTaskId)
  }

  private static func timestamp(_ millis: Int64) -> String {
    guard millis > 0 else { return "pending" }
    return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
  }

  private static func captures(_ pattern: String, in value: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, options: [], range: range) else { return nil }
    return (1..<match.numberOfRanges).compactMap { index in
      let captureRange = match.range(at: index)
      guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: value) else { return nil }
      return String(value[swiftRange])
    }
  }
}
