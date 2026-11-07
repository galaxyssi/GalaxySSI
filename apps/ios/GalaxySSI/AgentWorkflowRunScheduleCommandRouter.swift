import Foundation

struct AgentScheduledReplyVisibility: Equatable, Sendable {
  enum Rule: Equatable, Sendable { case hidden, unlessRich }
  private let rules: [String: [String: Rule]]

  init(tasks: [AgentProactiveTask], runs: [AgentProactiveRun]) {
    let grouped = Dictionary(grouping: runs, by: \.taskId)
    var result: [String: [String: Rule]] = [:]
    for task in tasks where task.action.isConversationSchedule {
      let conversation = task.action.conversationId
      guard !conversation.isBlank, let history = grouped[task.taskId] else { continue }
      let ordered = history.sorted {
        ($0.scheduledForMillis, $0.runId) < ($1.scheduledForMillis, $1.runId)
      }
      var previous: AgentProactiveRun?
      var older: AgentProactiveRun?
      for run in ordered {
        if let previous, previous.scheduledForMillis < run.scheduledForMillis { older = previous }
        if run.status == .unverified && run.errorCode == "phone_observation_unverified" {
          result[conversation, default: [:]][run.runId] = .hidden
        } else if run.status.terminal, older?.status == run.status, older?.resultSummary == run.resultSummary {
          result[conversation, default: [:]][run.runId] = .unlessRich
        }
        if [.completed, .failed, .unverified].contains(run.status) { previous = run }
      }
    }
    rules = result
  }

  func mayHide(conversation: String, token: String) -> Bool { rules[conversation]?[token] != nil }

  func hides(_ message: ChatMessage) -> Bool {
    guard !message.isMine, !message.isSystem, message.sourceConversationId.isBlank else { return false }
    switch rules[message.conversationId]?[message.turnId] {
    case .hidden?: return true
    case .unlessRich?: return message.richOutputJson.isBlank
    case nil: return false
    }
  }
}

enum AgentConversationSchedule {
  enum Command: Equatable {
    case save(prompt: String, trigger: AgentProactiveTrigger?, frequency: String, new: Bool)
    case pause, resume, list
  }

  static let receiptStage = "local_conversation_schedule"
  static let occurrenceStage = "local_conversation_schedule_occurrence"

  static func parse(_ input: String, zone: String = TimeZone.current.identifier) -> Command? {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count <= 4_096, !text.hasSuffix("?"), !text.hasSuffix("\u{ff1f}") else { return nil }
    text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".!\u{3002}\u{ff01}"))
    switch text.lowercased() {
    case "scheduled tasks", "show scheduled tasks", "list scheduled tasks", "\u{5b9a}\u{65f6}\u{4efb}\u{52a1}",
         "\u{5b9a}\u{6642}\u{4efb}\u{52d9}", "\u{67e5}\u{770b}\u{5b9a}\u{65f6}\u{4efb}\u{52a1}": return .list
    case "stop", "pause", "stop scheduled task", "pause scheduled task", "\u{6682}\u{505c}",
         "\u{505c}\u{6b62}", "\u{66ab}\u{505c}", "\u{6682}\u{505c}\u{5b9a}\u{65f6}\u{4efb}\u{52a1}",
         "\u{505c}\u{6b62}\u{5b9a}\u{65f6}\u{4efb}\u{52a1}": return .pause
    case "resume scheduled task", "\u{6062}\u{590d}\u{5b9a}\u{65f6}\u{4efb}\u{52a1}",
         "\u{7ee7}\u{7eed}\u{5b9a}\u{65f6}\u{4efb}\u{52a1}": return .resume
    default: break
    }
    let new = strip(&text, #"^(?:add\s+|new\s+|\u65B0\u589E|\u65B0\u5EFA|\u53E6\u5916)\s*"#)
    let edit = strip(&text, #"^(?:change to\s+|\u6539[\u6210\u4E3A\u70BA]|\u66F4\u65B0[\u4E3A\u70BA])\s*"#)
    _ = strip(&text, #"^(?:please\s+|\u8BF7|\u8ACB|\u5E2E\u6211|\u5E6B\u6211)\s*"#)
    if let time = frequency(text, zone: zone) {
      var prompt = String(text[time.end...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,:\u{ff0c}\u{ff1a}\t"))
      _ = strip(&prompt, #"^(?:\u5E2E\u6211|\u5E6B\u6211)\s*"#)
      guard !prompt.isBlank || edit else { return nil }
      return .save(prompt: prompt, trigger: time.trigger,
        frequency: String(text[..<time.end]).trimmingCharacters(in: .whitespacesAndNewlines), new: new)
    }
    if edit, !text.isBlank,
       match(#"^(?:every\b|daily\b|weekdays?\b|\u6BCF|\u5DE5\u4F5C\u65E5)"#, text) == nil {
      return .save(prompt: text, trigger: nil, frequency: "", new: false)
    }
    return nil
  }

  static func frequency(_ text: String, zone: String) -> (trigger: AgentProactiveTrigger, end: String.Index)? {
    let interval = #"^(?:every\s+|\u6BCF\u9694?)[ \t]*([0-9\u4E00\u4E8C\u4E24\u5169\u4E09\u56DB\u4E94\u516D\u4E03\u516B\u4E5D\u5341]+)?\s*(minutes?\b|mins?\b|hours?\b|days?\b|\u5206[\u949F\u9418]|\u5C0F[\u65F6\u6642]|\u5929)\s*(?:[\u6267\u57F7]\u884C\u4E00\u6B21|\u4E00\u6B21)?"#
    if let m = match(interval, text), let count = number(m.1[0].ifBlank("1")) {
      let unit = m.1[1].lowercased()
      let multiplier = unit.hasPrefix("m") || unit.hasPrefix("\u{5206}") ? 60 :
        unit.hasPrefix("h") || unit.hasPrefix("\u{5c0f}") ? 3_600 : 86_400
      let (seconds, overflow) = Int64(count).multipliedReportingOverflow(by: Int64(multiplier))
      guard !overflow, let trigger = try? AgentProactiveTrigger(kind: .interval, timeZone: zone, intervalSeconds: seconds)
      else { return nil }
      return (trigger, m.0)
    }
    let english = #"^(daily|weekdays?|weekly on (?:sun|mon|tue|wed|thu|fri|sat)(?:day)?)\s+(?:at\s+)?([0-9]{1,2}):([0-9]{2})(?![0-9])"#
    let chinese = #"^(\u6BCF[\u5929\u65E5]|(?:\u6BCF\u4E2A)?\u5DE5\u4F5C\u65E5|\u6BCF[\u5468\u9031][\u4E00\u4E8C\u4E09\u56DB\u4E94\u516D\u65E5\u5929])\s*(\u65E9\u4E0A|\u4E0A\u5348|\u4E0B\u5348|\u665A\u4E0A|\u4E2D\u5348)?\s*([0-9\u4E00\u4E8C\u4E24\u5169\u4E09\u56DB\u4E94\u516D\u4E03\u516B\u4E5D\u5341]+)(?::([0-9]{1,2})(?![0-9])|[\u70B9\u9EDE\u65F6\u6642](?:([0-9\u4E00\u4E8C\u4E09\u56DB\u4E94\u516D\u4E03\u516B\u4E5D\u5341]+)\u5206?|(\u534A))?)"#
    var hour: Int
    let minute: Int
    let day: String
    let end: String.Index
    if let m = match(english, text), let h = Int(m.1[1]), let min = Int(m.1[2]) {
      hour = h; minute = min; end = m.0
      let prefix = m.1[0].lowercased()
      if prefix.hasPrefix("weekday") { day = "1-5" }
      else if prefix == "daily" { day = "*" }
      else {
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        guard let index = names.firstIndex(where: { prefix.dropFirst("weekly on ".count).hasPrefix($0) }) else { return nil }
        day = String(index)
      }
    } else if let m = match(chinese, text), let h = number(m.1[2]),
              let min = number(m.1[5].isEmpty ? m.1[3].ifBlank(m.1[4]).ifBlank("0") : "30") {
      hour = h; minute = min; end = m.0
      if ["\u{4e0b}\u{5348}", "\u{665a}\u{4e0a}", "\u{4e2d}\u{5348}"].contains(m.1[1]), (1...11).contains(hour) { hour += 12 }
      let prefix = m.1[0]
      if prefix.hasSuffix("\u{5de5}\u{4f5c}\u{65e5}") { day = "1-5" }
      else if ["\u{6bcf}\u{5929}", "\u{6bcf}\u{65e5}"].contains(prefix) { day = "*" }
      else { day = String(number(String(prefix.suffix(1))) ?? 0) }
    } else { return nil }
    guard (0...23).contains(hour), (0...59).contains(minute),
          let trigger = try? AgentProactiveTrigger(kind: .cron, cron: "\(minute) \(hour) * * \(day)", timeZone: zone)
    else { return nil }
    return (trigger, end)
  }

  private static func number(_ text: String) -> Int? {
    if let value = Int(text) { return value }
    let digits = Array("\u{96f6}\u{4e00}\u{4e8c}\u{4e09}\u{56db}\u{4e94}\u{516d}\u{4e03}\u{516b}\u{4e5d}")
    func digit(_ value: String) -> Int? {
      if value == "\u{4e24}" || value == "\u{5169}" { return 2 }
      return value.count == 1 ? value.first.flatMap { digits.firstIndex(of: $0) } : nil
    }
    let parts = text.components(separatedBy: "\u{5341}")
    if parts.count == 2, let tens = parts[0].isEmpty ? 1 : digit(parts[0]),
       let ones = parts[1].isEmpty ? 0 : digit(parts[1]) { return tens * 10 + ones }
    return digit(text)
  }

  private static func strip(_ text: inout String, _ pattern: String) -> Bool {
    guard let (end, _) = match(pattern, text) else { return false }
    text = String(text[end...])
    return true
  }

  private static func match(_ pattern: String, _ text: String) -> (String.Index, [String])? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let full = Range(match.range, in: text) else { return nil }
    return (full.upperBound, (1..<match.numberOfRanges).map { index in
      Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
    })
  }

  static func targetsDesktop(_ prompt: String) -> Bool {
    match(#"(?:\b(?:windows|desktop|computer|macos)\b|\u7535\u8111|\u96FB\u8166)"#, prompt) != nil
  }

  static func expectsPhone(_ goal: String) -> Bool {
    !targetsDesktop(goal) && (AgentTaskIntentClassifier.classify(goal: goal).intent == .phoneControl ||
      match(#"\b(?:timer|countdown|alarm)\b|\u8BA1\u65F6\u5668|\u5012\u8BA1\u65F6|\u95F9\u949F"#, goal) != nil)
  }

  static let remoteContract = """
  This is a scheduled occurrence. Do not substitute a Desktop action for a phone action. Return one JSON object with protocol="galaxyssi.schedule-outcome.v1", outcome="completed"|"failed"|"blocked", summary (in the user's language), execution_device="desktop"|"none", and evidence (actual tool observations or sources). Never claim completion without observed evidence.
  """

  struct Outcome {
    var status: AgentProactiveRunStatus
    var summary: String
    var code: String = ""
  }

  static func remoteOutcome(_ raw: String, desktop: Bool) -> Outcome {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```json"), text.hasSuffix("```") {
      text = String(text.dropFirst(7).dropLast(3))
    }
    guard let receipt = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)),
          receipt["protocol"] == "galaxyssi.schedule-outcome.v1" else {
      return .init(status: .unverified, summary: raw, code: "missing_execution_outcome")
    }
    let summary = (receipt["summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if ["failed", "blocked"].contains(receipt["outcome"] ?? "") {
      return .init(status: .failed, summary: summary, code: "remote_schedule_failed")
    }
    let device = receipt["execution_device"] ?? ""
    guard receipt["outcome"] == "completed", !summary.isEmpty,
          !(receipt["evidence"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          desktop ? device == "desktop" : ["desktop", "none"].contains(device) else {
      return .init(status: .unverified, summary: summary, code: "missing_execution_evidence")
    }
    return .init(status: .completed, summary: summary)
  }

  static func localOutcome(_ task: AgentTaskRecord, goal: String) -> Outcome {
    let summary = task.result.ifBlank(task.verification)
    if task.phase == .cancelled { return .init(status: .cancelled, summary: summary, code: "schedule_cancelled") }
    let actions = task.activePlan?.historyForReplan() ?? task.lastCompletedNativeAction.map { [$0] } ?? []
    if actions.contains(where: AgentCompletionEvidencePolicy.hasUnverifiedOutcome) {
      return .init(status: .unverified, summary: summary, code: "phone_observation_unverified")
    }
    guard task.phase == .completed else {
      return .init(status: .failed, summary: summary, code: "schedule_execution_failed")
    }
    if expectsPhone(goal) {
      let completed = actions.filter { $0.status == .completed }
      let openApp = AgentNativeToolAgentActionAdapter.defaultToolId(.openApp)
      let alarm = AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm)
      guard task.executionLocationTrusted, task.executionLocationKind == .phone, !completed.isEmpty,
            !completed.contains(where: { action in
              let tool = action.parameters["tool_id"] ?? action.target
              if tool == openApp { return true }
              guard tool == alarm else { return false }
              guard let evidence = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(action.evidence.utf8))
              else { return true }
              return AgentObservedOutputFields.output(evidence)?["metadata"]?.objectValue?.string("completion_verified") != "true"
            }) else {
        return .init(status: .unverified, summary: summary, code: "phone_observation_unverified")
      }
    }
    return .init(status: .completed, summary: summary)
  }

  static func receiptTaskID(_ message: ChatMessage) -> String? {
    guard !message.isMine, !message.isSystem, message.sourceConversationId.isBlank,
          message.remoteMessageId == AgentScheduleFollowupPolicy.receiptId(turnId: message.turnId),
          let trace = message.deliveryTrace.first, trace.stage == receiptStage, !trace.detail.isEmpty
    else { return nil }
    return trace.detail
  }

  static func presentation(_ message: ChatMessage, task: AgentProactiveTask?, language: String) -> ChatMessage {
    guard let id = receiptTaskID(message) else { return message }
    var projected = message
    if let task, task.taskId == id, task.action.isConversationSchedule,
       task.action.conversationId == message.conversationId {
      projected.content = [task.name, task.action.scheduleText, state(task, language: language)]
        .filter { !$0.isBlank }.joined(separator: "\n")
    } else {
      projected.content = GalaxySSILocalization.string("galaxyssi.schedule.removed",
        fallback: "Schedule no longer available", language: language)
    }
    projected.richOutputJson = ""
    return projected
  }

  static func remotePresentation(_ message: ChatMessage) -> ChatMessage {
    let outcome = remoteOutcome(message.content, desktop: false)
    guard outcome.code != "missing_execution_outcome", !outcome.summary.isBlank else { return message }
    var projected = message
    projected.content = outcome.summary
    let blocks = AgentRichContentCodec.decode(message.richOutputJson).filter {
      !$0.text.contains("galaxyssi.schedule-outcome.v1")
    }
    projected.richOutputJson = blocks.isEmpty ? "" :
      AgentRichContentCodec.encode(AgentRichContentCodec.fromText(outcome.summary) + blocks)
    return projected
  }

  static func state(_ task: AgentProactiveTask, language: String) -> String {
    GalaxySSILocalization.string(task.enabled ? "galaxyssi.schedule.enabled" : "galaxyssi.schedule.paused",
      fallback: task.enabled ? "Enabled" : "Paused", language: language)
  }

  static func runID(task: AgentProactiveTask, scheduled: Int64) -> String {
    let hash = Array(AgentModelLoopRecoveryIdentity.sha256("\(task.taskId):\(task.revision):\(scheduled)").prefix(32))
    return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hash[$0]) }.joined(separator: "-").uppercased()
  }

  static func revision(_ run: AgentProactiveRun) -> Int? {
    guard let value = try? JSONDecoder().decode([String: Int].self, from: Data(run.causeJson.utf8)) else { return nil }
    return value["schedule_revision"]
  }
}

enum AgentScheduleFollowupPolicy {
  static let receiptStage = "local_workflow_schedule_receipt"

  static func receiptId(turnId: String) -> String { "schedule-command:" + turnId }

  static func target(before outgoing: ChatMessage, messages: [ChatMessage], liveTaskIds: Set<String>,
                     stage: String = receiptStage) -> String? {
    guard let prior = AgentOwnedOperationContext.previousRequest(before: outgoing, in: messages),
          let index = messages.firstIndex(where: { $0.id == outgoing.id }),
          let sourceIndex = messages[..<index].firstIndex(where: { $0.id == prior.id }) else { return nil }
    let turn = prior.turnId.ifBlank(prior.id.uuidString)
    let ids = Set(messages[(sourceIndex + 1)..<index].compactMap { reply -> String? in
      guard !reply.isMine, !reply.isSystem, reply.conversationId == prior.conversationId,
            reply.contactId == prior.contactId, reply.sourceConversationId.isBlank, reply.turnId == turn,
            [.delivered, .read].contains(reply.deliveryStatus),
            reply.remoteMessageId == receiptId(turnId: turn),
            let receipt = reply.deliveryTrace.first, receipt.stage == stage,
            prior.deliveryTrace.contains(where: { $0.stage == stage && $0.detail == receipt.detail }),
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
