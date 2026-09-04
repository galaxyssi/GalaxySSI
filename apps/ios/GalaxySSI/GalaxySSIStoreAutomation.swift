import Foundation

extension GalaxySSIStore {
  func automationTasks() -> [AgentProactiveTask] {
    Self.sortedAutomationTasks(proactiveTasks)
  }

  func automationTask(id taskId: String) -> AgentProactiveTask? {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return proactiveTasks.first { $0.taskId == clean }
  }

  func automationRuns(taskId: String, limit: Int = 50) -> [AgentProactiveRun] {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    return proactiveRuns
      .filter { $0.taskId == clean }
      .sorted { $0.scheduledForMillis > $1.scheduledForMillis }
      .prefix(max(0, limit))
      .map { $0 }
  }

  func recentAutomationRuns(limit: Int = 30) -> [AgentProactiveRun] {
    proactiveRuns
      .sorted { $0.scheduledForMillis > $1.scheduledForMillis }
      .prefix(max(0, limit))
      .map { $0 }
  }

  func queuedAutomationRuns(limit: Int = 8) -> [AgentProactiveRun] {
    proactiveRuns
      .filter { $0.status == .queued }
      .sorted { $0.scheduledForMillis < $1.scheduledForMillis }
      .prefix(max(0, limit))
      .map { $0 }
  }

  @discardableResult
  func claimDueAutomationTasks(nowMillis: Int64? = nil) -> Int {
    let now = max(nowMillis ?? Self.nowMillis(), 0)
    var claimed = 0
    for task in automationTasks() {
      guard task.enabled,
            task.nextRunAtMillis > 0,
            task.nextRunAtMillis <= now else {
        continue
      }
      if AgentProactiveTaskScheduler.shouldDisable(task: task, nowMillis: now) {
        guard let disabled = try? AgentProactiveTask(
          taskId: task.taskId,
          name: task.name,
          trigger: task.trigger,
          action: task.action,
          policy: task.policy,
          enabled: false,
          nextRunAtMillis: 0,
          lastRunAtMillis: task.lastRunAtMillis,
          lastStatus: task.lastStatus,
          runCount: task.runCount,
          consecutiveFailures: task.consecutiveFailures,
          revision: task.revision + 1,
          createdAtMillis: task.createdAtMillis,
          updatedAtMillis: now
        ) else {
          continue
        }
        replaceAutomationTask(disabled)
        continue
      }
      guard let due = try? AgentProactiveTaskScheduler.dueOccurrences(task: task, nowMillis: now),
            let scheduledTask = try? AgentProactiveTask(
              taskId: task.taskId,
              name: task.name,
              trigger: task.trigger,
              action: task.action,
              policy: task.policy,
              enabled: task.enabled,
              nextRunAtMillis: due.nextRunAtMillis,
              lastRunAtMillis: task.lastRunAtMillis,
              lastStatus: task.lastStatus,
              runCount: task.runCount,
              consecutiveFailures: task.consecutiveFailures,
              revision: task.revision,
              createdAtMillis: task.createdAtMillis,
              updatedAtMillis: now
            ) else {
        continue
      }

      var updatedTask = scheduledTask
      for occurrence in due.occurrences {
        let isSkipped = occurrence.status == .skipped
        guard let run = try? AgentProactiveRun(
          runId: "ios-proactive-run-\(UUID().uuidString.lowercased())",
          taskId: task.taskId,
          scheduledForMillis: occurrence.scheduledForMillis,
          status: occurrence.status,
          causeJson: "{\"source\":\"scheduler\",\"scheduled_for_millis\":\(occurrence.scheduledForMillis)}",
          startedAtMillis: isSkipped ? now : 0,
          completedAtMillis: isSkipped ? now : 0,
          resultSummary: isSkipped ? "Occurrence skipped by misfire policy." : "Run queued by iOS scheduler."
        ) else {
          continue
        }
        proactiveRuns = Array((proactiveRuns + [run]).suffix(500))
        claimed += 1
        if isSkipped {
          updatedTask = (try? AgentProactiveTaskScheduler.recordOutcome(
            task: updatedTask,
            status: .skipped,
            completedAtMillis: now
          )) ?? updatedTask
        }
      }
      replaceAutomationTask(updatedTask)
    }
    return claimed
  }

  @discardableResult
  func beginAutomationRun(id runId: String, nowMillis: Int64? = nil) -> AgentProactiveRun? {
    let clean = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = proactiveRuns.firstIndex(where: { $0.runId == clean }),
          proactiveRuns[index].status == .queued,
          let task = automationTask(id: proactiveRuns[index].taskId) else {
      return nil
    }
    let active = proactiveRuns.filter {
      $0.taskId == task.taskId && [.running, .waiting, .retrying].contains($0.status)
    }.count
    guard active < task.policy.maxConcurrency else { return nil }
    let now = max(nowMillis ?? Self.nowMillis(), 0)
    guard let running = try? AgentProactiveRun(
      runId: proactiveRuns[index].runId,
      taskId: proactiveRuns[index].taskId,
      scheduledForMillis: proactiveRuns[index].scheduledForMillis,
      status: .running,
      attempt: proactiveRuns[index].attempt,
      causeJson: proactiveRuns[index].causeJson,
      startedAtMillis: now,
      resultSummary: "Run started on iOS."
    ) else {
      return nil
    }
    proactiveRuns[index] = running
    return running
  }

  @discardableResult
  func finishAutomationRun(
    id runId: String,
    status: AgentProactiveRunStatus,
    resultSummary: String,
    errorCode: String = "",
    nowMillis: Int64? = nil
  ) -> Bool {
    let clean = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = proactiveRuns.firstIndex(where: { $0.runId == clean }),
          !proactiveRuns[index].status.terminal,
          let task = automationTask(id: proactiveRuns[index].taskId) else {
      return false
    }
    let now = max(nowMillis ?? Self.nowMillis(), 0)
    guard let finished = try? AgentProactiveRun(
      runId: proactiveRuns[index].runId,
      taskId: proactiveRuns[index].taskId,
      scheduledForMillis: proactiveRuns[index].scheduledForMillis,
      status: status,
      attempt: proactiveRuns[index].attempt,
      causeJson: proactiveRuns[index].causeJson,
      startedAtMillis: proactiveRuns[index].startedAtMillis,
      completedAtMillis: now,
      resultSummary: resultSummary,
      errorCode: errorCode
    ),
    let updatedTask = try? AgentProactiveTaskScheduler.recordOutcome(
      task: task,
      status: status,
      completedAtMillis: now
    ) else {
      return false
    }
    proactiveRuns[index] = finished
    replaceAutomationTask(updatedTask)
    return true
  }

  func recentWorkflowExecutions(limit: Int = AgentWorkflowExecutionHistoryStore.defaultRecentLimit) -> [AgentWorkflowExecutionRecord] {
    workflowExecutionHistoryStore.recent(limit)
  }

  func workflowExecutions(taskId: String, limit: Int = 50) -> [AgentWorkflowExecutionRecord] {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    return workflowExecutionHistoryStore.listAll()
      .filter { $0.workflowId == clean }
      .sorted { $0.startedAtMillis > $1.startedAtMillis }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func recordWorkflowExecution(_ record: AgentWorkflowExecutionRecord) {
    try? workflowExecutionHistoryStore.upsert(record)
  }

  func completeWorkflowExecution(
    id: String,
    status: AgentWorkflowExecutionStatus,
    resultSummary: String
  ) {
    guard let current = workflowExecutionHistoryStore.findById(id),
      let updated = try? AgentWorkflowExecutionRecord(
        id: current.id,
        workflowId: current.workflowId,
        workflowName: current.workflowName,
        source: current.source,
        status: status,
        startedAtMillis: current.startedAtMillis,
        completedAtMillis: Int64(Date().timeIntervalSince1970 * 1_000),
        resultSummary: resultSummary
      ) else {
      return
    }
    try? workflowExecutionHistoryStore.upsert(updated)
  }

  func makeAutomationTaskDraft(name: String = "", prompt: String = "") -> AgentProactiveTask {
    let now = Self.nowMillis()
    let taskId = "ios-proactive-\(UUID().uuidString.lowercased())"
    return try! AgentProactiveTask(
      taskId: taskId,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("New proactive task"),
      trigger: AgentProactiveTrigger(
        kind: .manual,
        timeZone: TimeZone.autoupdatingCurrent.identifier
      ),
      action: AgentProactiveAction(
        kind: .agent,
        targetId: defaultAutomationAgentTargetId(),
        prompt: prompt
      ),
      createdAtMillis: now,
      updatedAtMillis: now
    )
  }

  @discardableResult
  func saveAutomationTask(_ task: AgentProactiveTask) throws -> AgentProactiveTask {
    let now = Self.nowMillis()
    let existing = automationTask(id: task.taskId)
    var stored = try AgentProactiveTask(
      taskId: task.taskId,
      name: task.name,
      trigger: task.trigger,
      action: task.action,
      policy: task.policy,
      enabled: task.enabled,
      nextRunAtMillis: task.nextRunAtMillis,
      lastRunAtMillis: task.lastRunAtMillis,
      lastStatus: task.lastStatus,
      runCount: task.runCount,
      consecutiveFailures: task.consecutiveFailures,
      revision: existing == nil ? max(task.revision, 1) : max(existing?.revision ?? task.revision, task.revision) + 1,
      createdAtMillis: existing?.createdAtMillis ?? (task.createdAtMillis > 0 ? task.createdAtMillis : now),
      updatedAtMillis: now
    )
    let nextRun = stored.enabled ? (try AgentProactiveTaskScheduler.initialNextRun(task: stored, nowMillis: now)) : 0
    stored = try AgentProactiveTask(
      taskId: stored.taskId,
      name: stored.name,
      trigger: stored.trigger,
      action: stored.action,
      policy: stored.policy,
      enabled: stored.enabled,
      nextRunAtMillis: nextRun,
      lastRunAtMillis: stored.lastRunAtMillis,
      lastStatus: stored.lastStatus,
      runCount: stored.runCount,
      consecutiveFailures: stored.consecutiveFailures,
      revision: stored.revision,
      createdAtMillis: stored.createdAtMillis,
      updatedAtMillis: stored.updatedAtMillis
    )
    proactiveTasks.removeAll { $0.taskId == stored.taskId }
    proactiveTasks = Array(Self.sortedAutomationTasks(proactiveTasks + [stored]).prefix(200))
    return stored
  }

  @discardableResult
  func setAutomationTaskEnabled(id taskId: String, enabled: Bool) throws -> Bool {
    guard var task = automationTask(id: taskId) else { return false }
    task = try AgentProactiveTask(
      taskId: task.taskId,
      name: task.name,
      trigger: task.trigger,
      action: task.action,
      policy: task.policy,
      enabled: enabled,
      nextRunAtMillis: enabled ? try AgentProactiveTaskScheduler.initialNextRun(task: task, nowMillis: Self.nowMillis()) : 0,
      lastRunAtMillis: task.lastRunAtMillis,
      lastStatus: task.lastStatus,
      runCount: task.runCount,
      consecutiveFailures: task.consecutiveFailures,
      revision: task.revision + 1,
      createdAtMillis: task.createdAtMillis,
      updatedAtMillis: Self.nowMillis()
    )
    proactiveTasks.removeAll { $0.taskId == task.taskId }
    proactiveTasks = Array(Self.sortedAutomationTasks(proactiveTasks + [task]).prefix(200))
    return true
  }

  @discardableResult
  func deleteAutomationTask(id taskId: String) -> Bool {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    let before = proactiveTasks.count
    proactiveTasks.removeAll { $0.taskId == clean }
    proactiveRuns.removeAll { $0.taskId == clean }
    workflowExecutionHistoryStore.deleteForWorkflow(clean)
    return before != proactiveTasks.count
  }

  @discardableResult
  func triggerAutomationTaskNow(id taskId: String) throws -> AgentProactiveRun {
    guard let task = automationTask(id: taskId) else {
      throw AgentProactiveTaskError.invalid("Proactive task not found")
    }
    let now = Self.nowMillis()
    let run = try AgentProactiveRun(
      runId: "ios-proactive-run-\(UUID().uuidString.lowercased())",
      taskId: task.taskId,
      scheduledForMillis: now,
      status: .queued,
      causeJson: "{\"source\":\"manual\"}",
      resultSummary: "Run queued on iOS scheduler."
    )
    try workflowExecutionHistoryStore.upsert(AgentWorkflowExecutionRecord(
      id: run.runId,
      workflowId: task.taskId,
      workflowName: task.name,
      source: .manual,
      status: .running,
      startedAtMillis: now,
      resultSummary: run.resultSummary
    ))
    let updatedTask = try AgentProactiveTask(
      taskId: task.taskId,
      name: task.name,
      trigger: task.trigger,
      action: task.action,
      policy: task.policy,
      enabled: task.enabled,
      nextRunAtMillis: task.nextRunAtMillis,
      lastRunAtMillis: task.lastRunAtMillis,
      lastStatus: .queued,
      runCount: task.runCount,
      consecutiveFailures: task.consecutiveFailures,
      revision: task.revision,
      createdAtMillis: task.createdAtMillis,
      updatedAtMillis: now
    )
    proactiveRuns = Array((proactiveRuns + [run]).suffix(500))
    replaceAutomationTask(updatedTask)
    return run
  }

  func acceptRemoteWebhook(
    taskId: String,
    eventId: String,
    payload: [String: Any],
    sourceDesktopId: String
  ) -> (task: AgentProactiveTask, run: AgentProactiveRun, accepted: Bool)? {
    let desktopId = sourceDesktopId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanEventId = eventId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !desktopId.isEmpty,
          !cleanEventId.isEmpty,
          (try? AgentProactiveTaskScheduler.requireIdentifier(cleanEventId, label: "Event id")) != nil,
          serverLinks.contains(where: { $0.desktopId == desktopId && $0.paired }),
          let task = automationTask(id: taskId),
          task.enabled,
          task.trigger.kind == .webhook,
          AgentProactiveTaskScheduler.remoteWebhookEventMatches(
            filter: task.trigger.eventFilter,
            payload: payload
          ) else {
      return nil
    }

    let runId = AgentProactiveTaskScheduler.stableRunId(
      taskId: task.taskId,
      occurrence: cleanEventId
    )
    let webhookStore = UserDefaultsAgentRemoteProactiveWebhookStore.shared
    guard webhookStore.consume(taskId: task.taskId, eventId: cleanEventId) else {
      guard let existing = proactiveRuns.first(where: { $0.runId == runId }) else {
        return nil
      }
      return (task: task, run: existing, accepted: false)
    }

    let cause: [String: Any] = [
      "type": "webhook",
      "event_id": cleanEventId,
      "source_desktop_id": desktopId,
      "payload": payload
    ]
    let causeJson = (try? JSONSerialization.data(withJSONObject: cause))
      .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    let now = Self.nowMillis()
    guard let run = try? AgentProactiveRun(
      runId: runId,
      taskId: task.taskId,
      scheduledForMillis: now,
      status: .queued,
      causeJson: causeJson,
      startedAtMillis: now,
      resultSummary: "Remote webhook queued."
    ) else {
      return nil
    }
    proactiveRuns = Array((proactiveRuns + [run]).suffix(500))
    return (task: task, run: run, accepted: true)
  }

  func claimDueAutomationExecutions(
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> [AgentProactiveBackgroundExecution] {
    var executions: [AgentProactiveBackgroundExecution] = []
    let candidates = proactiveTasks.filter {
      $0.enabled && $0.nextRunAtMillis > 0 && $0.nextRunAtMillis <= nowMillis
    }
    for task in candidates {
      guard let due = try? AgentProactiveTaskScheduler.dueOccurrences(
        task: task,
        nowMillis: nowMillis
      ), !due.occurrences.isEmpty else {
        continue
      }

      let queuedCount = due.occurrences.filter { $0.status == .queued }.count
      let updated = try? AgentProactiveTask(
        taskId: task.taskId,
        name: task.name,
        trigger: task.trigger,
        action: task.action,
        policy: task.policy,
        enabled: task.enabled,
        nextRunAtMillis: due.nextRunAtMillis,
        lastRunAtMillis: task.lastRunAtMillis,
        lastStatus: queuedCount > 0 ? .queued : .skipped,
        runCount: task.runCount,
        consecutiveFailures: task.consecutiveFailures,
        revision: task.revision,
        createdAtMillis: task.createdAtMillis,
        updatedAtMillis: nowMillis
      )
      guard let updated else { continue }
      proactiveTasks.removeAll { $0.taskId == task.taskId }
      proactiveTasks = Array(Self.sortedAutomationTasks(proactiveTasks + [updated]).prefix(200))

      for occurrence in due.occurrences {
        guard let run = try? AgentProactiveRun(
          runId: "ios-proactive-run-\(UUID().uuidString.lowercased())",
          taskId: task.taskId,
          scheduledForMillis: occurrence.scheduledForMillis,
          status: occurrence.status,
          causeJson: "{\"source\":\"background\"}",
          startedAtMillis: nowMillis,
          resultSummary: occurrence.status == .queued
            ? "Background Agent request queued."
            : "Occurrence skipped by proactive policy."
        ) else { continue }
        proactiveRuns = Array((proactiveRuns + [run]).suffix(500))
        if occurrence.status == .queued {
          executions.append(AgentProactiveBackgroundExecution(
            task: task,
            runId: run.runId,
            scheduledForMillis: occurrence.scheduledForMillis
          ))
        }
      }
    }
    return executions
  }

  @discardableResult
  func finishAutomationRun(
    id runId: String,
    status: AgentProactiveRunStatus,
    resultSummary: String,
    errorCode: String = ""
  ) -> Bool {
    let clean = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = proactiveRuns.firstIndex(where: { $0.runId == clean }) else {
      return false
    }
    let now = Self.nowMillis()
    let run = proactiveRuns[index]
    guard !run.status.terminal else { return false }
    guard let finished = try? AgentProactiveRun(
      runId: run.runId,
      taskId: run.taskId,
      scheduledForMillis: run.scheduledForMillis,
      status: status,
      attempt: run.attempt,
      causeJson: run.causeJson,
      startedAtMillis: run.startedAtMillis,
      completedAtMillis: now,
      resultSummary: resultSummary,
      errorCode: errorCode,
      linkedExecutionId: run.linkedExecutionId,
      teamRunId: run.teamRunId
    ) else { return false }
    var runs = proactiveRuns
    runs[index] = finished
    proactiveRuns = runs

    guard let task = automationTask(id: run.taskId),
          let updated = try? AgentProactiveTaskScheduler.recordOutcome(
            task: task,
            status: status,
            completedAtMillis: now
          ) else {
      return true
    }
    proactiveTasks.removeAll { $0.taskId == updated.taskId }
    proactiveTasks = Array(Self.sortedAutomationTasks(proactiveTasks + [updated]).prefix(200))
    return true
  }

  @discardableResult
  func cancelAutomationRun(id runId: String) -> Bool {
    let clean = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = proactiveRuns.firstIndex(where: { $0.runId == clean }),
          !proactiveRuns[index].status.terminal else {
      return false
    }
    let run = proactiveRuns[index]
    let cancelled = try? AgentProactiveRun(
      runId: run.runId,
      taskId: run.taskId,
      scheduledForMillis: run.scheduledForMillis,
      status: .cancelled,
      attempt: run.attempt,
      causeJson: run.causeJson,
      startedAtMillis: run.startedAtMillis,
      completedAtMillis: Self.nowMillis(),
      resultSummary: run.resultSummary,
      errorCode: run.errorCode,
      linkedExecutionId: run.linkedExecutionId,
      teamRunId: run.teamRunId
    )
    guard let cancelled else { return false }
    var runs = proactiveRuns
    runs[index] = cancelled
    proactiveRuns = runs
    if let task = automationTask(id: run.taskId) {
      try? workflowExecutionHistoryStore.upsert(AgentWorkflowExecutionRecord(
        id: run.runId,
        workflowId: task.taskId,
        workflowName: task.name,
        source: .manual,
        status: .cancelled,
        startedAtMillis: run.startedAtMillis,
        completedAtMillis: cancelled.completedAtMillis,
        resultSummary: cancelled.resultSummary
      ))
    }
    return true
  }

  private func defaultAutomationAgentTargetId() -> String {
    if contacts.contains(where: { !$0.deleted && ($0.id == "codex" || $0.galaxySSIId == "codex") }) {
      return "codex"
    }
    if contacts.contains(where: { !$0.deleted && ($0.id == "hermes" || $0.galaxySSIId == "hermes") }) {
      return "hermes"
    }
    return contacts.first(where: { !$0.deleted })?.id ?? "codex"
  }

  private static func sortedAutomationTasks(_ tasks: [AgentProactiveTask]) -> [AgentProactiveTask] {
    tasks.sorted { left, right in
      if left.enabled != right.enabled {
        return left.enabled && !right.enabled
      }
      let leftTime = left.nextRunAtMillis > 0 ? left.nextRunAtMillis : left.updatedAtMillis
      let rightTime = right.nextRunAtMillis > 0 ? right.nextRunAtMillis : right.updatedAtMillis
      if leftTime != rightTime {
        return leftTime > rightTime
      }
      return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
  }

  private func replaceAutomationTask(_ task: AgentProactiveTask) {
    proactiveTasks.removeAll { $0.taskId == task.taskId }
    proactiveTasks = Array(Self.sortedAutomationTasks(proactiveTasks + [task]).prefix(200))
  }
}
