import Foundation

extension SignalASIStore {
  func agentSessions(includeArchived: Bool = false) -> [AgentConversation] {
    mergedAgentConversations()
      .filter { includeArchived || $0.status == .active }
  }

  func searchAgentSessions(_ query: String, includeArchived: Bool = false) -> [AgentConversation] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return agentSessions(includeArchived: includeArchived)
    }
    return agentSessions(includeArchived: includeArchived)
      .filter { conversation in
        [
          conversation.title,
          conversation.summary,
          conversation.selectedModelOrAgent,
          conversation.contextPolicy,
          conversation.id
        ].contains {
          $0.range(of: clean, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
  }

  func agentSession(id conversationId: String) -> AgentConversation? {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return mergedAgentConversations().first { $0.id == clean }
  }

  func agentSessionDestination(id conversationId: String) -> String? {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }

    var currentID = clean
    var visited: Set<String> = []
    while visited.insert(currentID).inserted,
          let conversation = agentConversations.first(where: { $0.id == currentID }),
          !conversation.mergedIntoConversationId.isBlank {
      currentID = conversation.mergedIntoConversationId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !currentID.isEmpty else { return nil }
    }

    return agentSession(id: currentID)?.id
  }

  @discardableResult
  func createAgentSession(title: String = "") -> AgentConversation {
    createAgentSession(
      title: title,
      createdByAgent: false,
      parentConversationId: "",
      globalTopicKey: ""
    )
  }

  @discardableResult
  func createAgentConversation(
    title: String,
    parentConversationId: String = "",
    globalTopicKey: String = ""
  ) -> AgentConversation {
    createAgentSession(
      title: title,
      createdByAgent: true,
      parentConversationId: parentConversationId,
      globalTopicKey: globalTopicKey
    )
  }

  private func createAgentSession(
    title: String,
    createdByAgent: Bool,
    parentConversationId: String,
    globalTopicKey: String
  ) -> AgentConversation {
    let now = Self.nowMillis()
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("New session")
    let session = AgentConversation(
      id: "ios-agent-\(UUID().uuidString.lowercased())",
      title: cleanTitle,
      createdAt: now,
      updatedAt: now,
      selectedModelOrAgent: "Automatic",
      createdByAgent: createdByAgent,
      parentConversationId: parentConversationId.trimmingCharacters(in: .whitespacesAndNewlines),
      globalTopicKey: globalTopicKey.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    persistAgentConversation(session)
    if !createdByAgent {
      activeAgentConversationId = session.id
    }
    return session
  }

  @discardableResult
  func switchAgentSession(_ conversationId: String) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var session = agentSession(id: clean) else { return false }
    if session.status == .archived {
      session.status = .active
      session.updatedAt = Self.nowMillis()
      persistAgentConversation(session)
    }
    activeAgentConversationId = session.id
    return true
  }

  @discardableResult
  func renameAgentSession(id conversationId: String, title: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank(conversation.title)
    }
  }

  @discardableResult
  func setAgentSessionPinned(id conversationId: String, pinned: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.pinned = pinned }
  }

  @discardableResult
  func setAgentSessionPrivateMode(id conversationId: String, privateMode: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.privateMode = privateMode }
  }

  @discardableResult
  func setAgentSessionTrackingPaused(id conversationId: String, paused: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.trackingPaused = paused }
  }

  @discardableResult
  func setAgentSessionContextPolicy(id conversationId: String, policy: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.contextPolicy = ["minimal", "balanced", "extended"].contains(policy) ? policy : "balanced"
    }
  }

  @discardableResult
  func setAgentSessionSelectedModelOrAgent(id conversationId: String, label: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.selectedModelOrAgent = label.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank("Automatic")
    }
  }

  @discardableResult
  func updateAgentSessionSummary(id conversationId: String, summary: String) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  @discardableResult
  func mergeAgentSessionIntoParent(id conversationId: String) -> AgentConversationMergeResult {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let source = agentSession(id: clean) else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: nil, targetConversation: nil,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .sourceNotFound
      )
    }
    guard source.createdByAgent else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: nil,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .notAgentCreated
      )
    }
    guard source.mergedIntoConversationId.isBlank else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: nil,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .alreadyMerged
      )
    }
    guard let target = agentSession(id: source.parentConversationId) else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: nil,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .targetNotFound
      )
    }
    guard source.id != target.id else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: target,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .sameConversation
      )
    }
    guard source.privateMode == target.privateMode else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: target,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .privacyMismatch
      )
    }

    let sourceMessages = agentSessionMessages(source.id).filter { !$0.isSystem }
    for message in sourceMessages {
      var copy = message
      copy.id = UUID()
      copy.conversationId = target.id
      copy.remoteMessageId = ""
      copy.sourceConversationId = source.id
      copy.sourceConversationTitle = source.title
      messagesByContact[copy.contactId, default: []].append(copy)
    }

    let now = Self.nowMillis()
    var mergedSource = source
    mergedSource.status = .archived
    mergedSource.trackingPaused = true
    mergedSource.mergedIntoConversationId = target.id
    mergedSource.mergedAtMillis = now
    mergedSource.updatedAt = now

    var mergedTarget = target
    mergedTarget.status = .active
    mergedTarget.summary = mergedSessionSummary(target.summary, source.summary)
    mergedTarget.inputTokens = saturatingAdd(target.inputTokens, source.inputTokens)
    mergedTarget.outputTokens = saturatingAdd(target.outputTokens, source.outputTokens)
    mergedTarget.costMicros = saturatingAdd(target.costMicros, source.costMicros)
    mergedTarget.updatedAt = max(target.updatedAt, source.updatedAt, now)

    agentTaskRecords = agentTaskRecords.map { task in
      guard task.sessionId == source.id else { return task }
      var rebound = task
      rebound.sessionId = target.id
      return rebound
    }
    persistAgentConversation(mergedSource)
    persistAgentConversation(mergedTarget)
    if activeAgentConversationId == source.id {
      activeAgentConversationId = target.id
    }
    save()
    return AgentConversationMergeResult(
      merged: true,
      sourceConversation: mergedSource,
      targetConversation: mergedTarget,
      copiedEntryCount: sourceMessages.count,
      skippedEntryCount: 0,
      failure: .none
    )
  }

  @discardableResult
  func archiveAgentSession(id conversationId: String) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let shouldClearActive = activeAgentConversationId == clean
    let changed = mutateAgentConversation(id: clean) { conversation in
      conversation.status = .archived
    }
    if changed && shouldClearActive {
      activeAgentConversationId = ""
    }
    return changed
  }

  @discardableResult
  func restoreAgentSession(id conversationId: String) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.status = .active }
  }

  @discardableResult
  func deleteAgentSession(id conversationId: String) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    let beforeConversations = agentConversations.count
    agentConversations.removeAll { $0.id == clean }
    var removedMessages = 0
    for contactId in Array(messagesByContact.keys) {
      guard var messages = messagesByContact[contactId] else { continue }
      let before = messages.count
      messages.removeAll { $0.conversationId == clean }
      removedMessages += before - messages.count
      if messages.isEmpty {
        messagesByContact.removeValue(forKey: contactId)
      } else {
        messagesByContact[contactId] = messages
      }
    }
    if activeAgentConversationId == clean {
      activeAgentConversationId = agentSessions().first?.id ?? ""
    }
    guard beforeConversations != agentConversations.count || removedMessages > 0 else { return false }
    AgentModelSelectionSettings.clearConversation(clean)
    save()
    return true
  }

  func agentSessionMessages(_ conversationId: String) -> [ChatMessage] {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    return messagesByContact.values
      .flatMap { $0 }
      .filter { $0.conversationId == clean }
      .sorted { $0.createdAt < $1.createdAt }
  }

  func agentSessionMetrics(_ conversationId: String) -> AgentSessionMetrics {
    let messages = agentSessionMessages(conversationId)
    let turnIds = Set(messages.map(\.turnId).filter { !$0.isBlank })
    let userTurns = messages.filter { $0.isMine && !$0.isSystem }.count
    let estimatedTokens = messages.reduce(0) { partial, message in
      partial + max(1, message.content.count / 4)
    }
    return AgentSessionMetrics(
      turnCount: max(turnIds.count, userTurns),
      messageCount: messages.count,
      taskCount: messages.filter { message in
        message.deliveryTrace.contains { $0.stage == "agent_started" || $0.stage == "agent_replied" }
      }.count,
      estimatedContextTokens: estimatedTokens,
      inputTokens: agentSession(id: conversationId)?.inputTokens ?? 0,
      outputTokens: agentSession(id: conversationId)?.outputTokens ?? 0,
      costMicros: agentSession(id: conversationId)?.costMicros ?? 0,
      lastResponseLatencyMillis: lastAgentResponseLatencyMillis(messages)
    )
  }
  @discardableResult
  private func mutateAgentConversation(
    id conversationId: String,
    mutate: (inout AgentConversation) -> Void
  ) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var conversation = agentSession(id: clean) else { return false }
    mutate(&conversation)
    conversation.updatedAt = Self.nowMillis()
    persistAgentConversation(conversation)
    return true
  }

  private func mergedSessionSummary(_ target: String, _ source: String) -> String {
    let targetSummary = target.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceSummary = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if targetSummary.isEmpty { return sourceSummary }
    if sourceSummary.isEmpty || targetSummary == sourceSummary { return targetSummary }
    return "\(targetSummary)\n\n\(sourceSummary)"
  }

  private func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let (value, overflow) = left.addingReportingOverflow(right)
    return overflow ? Int64.max : value
  }

  private func persistAgentConversation(_ conversation: AgentConversation) {
    let clean = conversation.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    var updated = conversation
    updated.id = clean
    let items = agentConversations.filter { $0.id != clean } + [updated]
    agentConversations = Array(Self.sortedAgentConversations(items).prefix(200))
  }

  private func mergedAgentConversations() -> [AgentConversation] {
    var byId: [String: AgentConversation] = [:]
    for conversation in agentConversations where !conversation.id.isBlank {
      byId[conversation.id] = conversation
    }
    for contact in contacts where isAgentSessionContact(contact) {
      let conversationId = defaultAgentConversationId(for: contact.id)
      let messages = agentSessionMessages(conversationId)
      guard !messages.isEmpty || contact.id == "hermes" else { continue }
      let createdAt = messages.map { Self.millis($0.createdAt) }.min() ?? Self.nowMillis()
      let updatedAt = messages.map { Self.millis($0.createdAt) }.max() ?? createdAt
      var conversation = byId[conversationId] ?? AgentConversation(
        id: conversationId,
        title: contact.displayName,
        createdAt: createdAt,
        updatedAt: updatedAt,
        selectedModelOrAgent: contact.displayName
      )
      conversation.title = conversation.title.ifBlank(contact.displayName)
      conversation.selectedModelOrAgent = conversation.selectedModelOrAgent.ifBlank(contact.displayName)
      conversation.updatedAt = max(conversation.updatedAt, updatedAt)
      byId[conversationId] = conversation
    }
    return Self.sortedAgentConversations(Array(byId.values))
  }

  private func isAgentSessionContact(_ contact: SignalASIContact) -> Bool {
    contact.id == "hermes" || contact.type == "agent" || contact.deliveryMode == .cloudAPI
  }

  private func defaultAgentConversationId(for contactId: String) -> String {
    "ios-\(contactId)"
  }

  func activeConversationId(for contactId: String) -> String {
    if let contact = contact(id: contactId),
       isAgentSessionContact(contact),
       let active = agentSession(id: activeAgentConversationId),
       active.status == .active,
       active.mergedIntoConversationId.isBlank {
      return active.id
    }
    return defaultAgentConversationId(for: contactId)
  }

  func recordAgentConversationActivity(
    conversationId: String,
    contactId: String,
    content: String,
    at date: Date
  ) {
    guard let contact = contact(id: contactId), isAgentSessionContact(contact) else { return }
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    let timestamp = Self.millis(date)
    var conversation = agentSession(id: clean) ?? AgentConversation(
      id: clean,
      title: inferredAgentSessionTitle(content: content, fallback: contact.displayName),
      createdAt: timestamp,
      updatedAt: timestamp,
      selectedModelOrAgent: contact.displayName
    )
    if conversation.title.isBlank || conversation.title == "New session" {
      conversation.title = inferredAgentSessionTitle(content: content, fallback: contact.displayName)
    }
    if conversation.selectedModelOrAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      conversation.selectedModelOrAgent = contact.displayName.ifBlank("Automatic")
    }
    conversation.updatedAt = max(conversation.updatedAt, timestamp)
    persistAgentConversation(conversation)
  }

  private func inferredAgentSessionTitle(content: String, fallback: String) -> String {
    let clean = content
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return fallback.ifBlank("New session") }
    return String(clean.prefix(48))
  }

  private static func sortedAgentConversations(_ conversations: [AgentConversation]) -> [AgentConversation] {
    conversations.sorted { left, right in
      if left.pinned != right.pinned {
        return left.pinned && !right.pinned
      }
      if left.updatedAt != right.updatedAt {
        return left.updatedAt > right.updatedAt
      }
      return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
  }

  private func lastAgentResponseLatencyMillis(_ messages: [ChatMessage]) -> Int64 {
    let ordered = messages.sorted { $0.createdAt < $1.createdAt }
    var lastUserAt: Date?
    var latestLatency: Int64 = 0
    for message in ordered {
      if message.isMine && !message.isSystem {
        lastUserAt = message.createdAt
      } else if !message.isMine && !message.isSystem, let start = lastUserAt {
        latestLatency = max(0, Self.millis(message.createdAt) - Self.millis(start))
      }
    }
    return latestLatency
  }

  static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }
}
