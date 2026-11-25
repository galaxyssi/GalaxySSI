import Foundation

enum AgentConversationScheduleProvenance {
  enum Origin: String { case editor, modelTool = "model_tool" }
  static let review = "legacy_review_required"
  static func turnKey(_ value: String) -> String { UUID(uuidString: value)?.uuidString ?? value }
  static func verified(_ task: AgentProactiveTask) -> Bool {
    !task.action.isConversationSchedule || Origin(rawValue: task.action.scheduleOrigin) != nil
  }
  static func requiresReview(_ task: AgentProactiveTask) -> Bool { !verified(task) }

  static func receiptOrigin(_ message: ChatMessage, task: AgentProactiveTask) -> Origin? {
    guard !message.isMine, !message.isSystem, message.sourceConversationId.isBlank,
      !task.action.scheduleText.isBlank,
      message.conversationId == task.action.conversationId,
      message.deliveryTrace.first?.stage == AgentConversationSchedule.receiptStage,
      message.deliveryTrace.first?.detail == task.taskId else { return nil }
    let origin: Origin
    if message.remoteMessageId.hasPrefix("schedule-editor:") { origin = .editor }
    else if message.remoteMessageId.hasPrefix("schedule-tool:" + task.taskId + ":") { origin = .modelTool }
    else { return nil }
    // iOS tool receipts were plain native text, not Android rich cards. Never trust schedule-command receipts.
    let prefix = task.name + "\n" + task.action.scheduleText
    guard message.content == prefix || message.content.hasPrefix(prefix + "\n") else { return nil }
    return origin
  }
  static func text(language: String) -> String {
    func value(_ locale: String, fallback: String) -> String {
      guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
      return bundle.localizedString(forKey: "schedule_legacy_review", value: fallback, table: "ScheduleProvenance")
    }
    let english = value("en", fallback: "Paused: review this older task and its time before resuming. Existing answers are retained.")
    return value(LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en", fallback: english)
  }
}

extension GalaxySSIStore {
  var schedulePreviewCacheKey: String {
    let tasks = proactiveTasks.filter(AgentConversationScheduleProvenance.requiresReview)
    let ids = Set(tasks.map(\.taskId))
    let taskKeys = tasks.map { "\($0.taskId):\($0.revision):\($0.action.scheduleOrigin)" }.sorted()
    let runKeys = proactiveRuns.filter { ids.contains($0.taskId) }.map { "\($0.taskId):\($0.runId)" }.sorted()
    return AgentModelLoopRecoveryIdentity.sha256((taskKeys + runKeys).joined(separator: "|"))
  }
  @discardableResult
  func reconcileConversationScheduleProvenance() -> Bool {
    var succeeded = true
    for original in proactiveTasks where original.action.isConversationSchedule && !AgentConversationScheduleProvenance.verified(original) {
      guard var task = automationTask(id: original.taskId) else { continue }
      let origin = task.action.scheduleOrigin.isEmpty ? savedScheduleOrigin(task) : nil
      if let origin {
        task.action.scheduleOrigin = origin.rawValue
        let tasks = proactiveTasks.map { $0.taskId == task.taskId ? task : $0 }
        if !commitConversationScheduleState(tasks: tasks, runs: proactiveRuns) { succeeded = false }
        continue
      }
      let now = Self.nowMillis()
      if task.action.scheduleOrigin != AgentConversationScheduleProvenance.review || task.enabled || task.nextRunAtMillis != 0 {
        guard task.revision < Int.max else { succeeded = false; continue }
        task.action.scheduleOrigin = AgentConversationScheduleProvenance.review
        task.enabled = false; task.nextRunAtMillis = 0; task.revision += 1; task.updatedAtMillis = now
      }
      let runs = proactiveRuns.map { run -> AgentProactiveRun in
        guard run.taskId == task.taskId, !run.status.terminal else { return run }
        var cancelled = run
        cancelled.status = .cancelled; cancelled.completedAtMillis = now; cancelled.errorCode = "legacy_schedule_review_required"
        return cancelled
      }
      let tasks = proactiveTasks.map { $0.taskId == task.taskId ? task : $0 }
      // Disable durably first. Tombstones reject new old-occurrence writes, never filter or rewrite history.
      if tasks != proactiveTasks || runs != proactiveRuns {
        guard commitConversationScheduleState(tasks: tasks, runs: runs) else { succeeded = false; continue }
      }
      let turns = proactiveRuns.filter { $0.taskId == task.taskId }.map(\.runId)
      if !chatHistoryDatabase.blockScheduleReplies(conversation: task.action.conversationId, turns: turns) { succeeded = false }
      NotificationService.cancelNotification(identifier: AgentConversationSchedule.replyAlertIdentifier(original))
    }
    return succeeded
  }
  private func savedScheduleOrigin(_ task: AgentProactiveTask) -> AgentConversationScheduleProvenance.Origin? {
    var cursor: GalaxySSIChatHistoryCursor?
    repeat {
      let page = chatHistoryDatabase.page(contactId: nil, conversationId: task.action.conversationId, before: cursor, pageSize: 50)
      for message in page.messages.reversed() {
        if let origin = AgentConversationScheduleProvenance.receiptOrigin(message, task: task) { return origin }
      }
      guard page.hasMore, let next = page.nextCursor, next != cursor else { return nil }
      cursor = next
    } while true
  }
  func admitsScheduledReply(conversation: String, turn: String) -> Bool {
    guard !turn.isEmpty, !conversation.isEmpty else { return true }
    if chatHistoryDatabase.isScheduleReplyBlocked(conversation: conversation, turn: turn) { return false }
    guard let run = proactiveRuns.first(where: { AgentConversationScheduleProvenance.turnKey($0.runId) == AgentConversationScheduleProvenance.turnKey(turn) }), let task = automationTask(id: run.taskId),
      task.action.isConversationSchedule, task.action.conversationId == conversation else {
      if let id = UUID(uuidString: turn), let source = chatHistoryDatabase.message(id: id), source.isMine,
        source.conversationId == conversation,
        source.deliveryTrace.contains(where: { $0.stage == AgentConversationSchedule.occurrenceStage }) { return false }
      return true
    }
    return task.enabled && AgentConversationScheduleProvenance.verified(task) && run.status != .cancelled &&
      AgentConversationSchedule.revision(run) == task.revision
  }
  func scheduleListPreview(_ message: ChatMessage) -> ChatMessage {
    guard !message.isMine, !message.isSystem, message.remoteMessageId.hasPrefix("scheduled-result:"),
      let run = proactiveRuns.first(where: { $0.runId == String(message.remoteMessageId.dropFirst("scheduled-result:".count)) }),
      let task = automationTask(id: run.taskId), task.action.conversationId == message.conversationId,
      AgentConversationScheduleProvenance.requiresReview(task), let separator = message.content.range(of: "\n\n") else { return message }
    var preview = message; preview.content = String(message.content[separator.upperBound...]); return preview
  }
}
