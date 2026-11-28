import Foundation

struct AgentLearningOutboxScope: Codable, Equatable {
  enum Kind: String, Codable { case cognition, autonomous, research }
  let kind: Kind
  let profile: String
  let source: Int64
  let resource: String
  let transport: GlobalResearchResourceTransport
  let task: String
  let action: String
  let conversation: String
  let turn: String
  let requestID: String
  let unit: String
  let stage: GlobalResearchDispatchStage?
  let leaseID: String
  let requestOwner: String
  private(set) var messageID = ""
  private(set) var topic = ""

  static func cognition(_ request: GalaxySSIGlobalCognitionDispatchRequest, profile: String) -> Self {
    .init(kind: .cognition, profile: profile, source: request.sourceMessageId, resource: request.resourceId,
      transport: request.transport, task: request.taskId, action: "", conversation: request.conversationId,
      turn: request.turnId, requestID: "", unit: "", stage: nil, leaseID: "", requestOwner: "")
  }

  static func autonomous(_ request: GalaxySSIGlobalAutonomousDispatchRequest, profile: String) -> Self {
    .init(kind: .autonomous, profile: profile, source: request.sourceMessageId, resource: request.resourceId,
      transport: request.transport, task: request.runId, action: request.actionId, conversation: request.conversationId,
      turn: request.turnId, requestID: "", unit: "", stage: nil, leaseID: "", requestOwner: "")
  }

  static func research(_ request: GlobalResearchDispatchRequest, profile: String) -> Self {
    .init(kind: .research, profile: profile, source: request.sourceMessageId, resource: request.resourceId,
      transport: request.transport, task: request.taskId, action: "", conversation: request.conversationId,
      turn: request.turnId, requestID: request.id, unit: request.unitId, stage: request.stage,
      leaseID: request.leaseId, requestOwner: request.ownerKey)
  }

  private var valid: Bool {
    source > 0 && transport == .pairedAgent && [profile, resource, task, conversation, turn].allSatisfy {
      !$0.isBlank && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) && $0.utf8.count <= 512
    } && [action, requestID, unit, leaseID, requestOwner].allSatisfy { $0.utf8.count <= 512 } &&
      (kind != .research || (!requestID.isBlank && stage != nil && !leaseID.isBlank && !requestOwner.isBlank))
  }

  func bound(messageID: String, topic: String, payload: [String: Any], profile: String,
             source: String, contact: String) -> Self? {
    guard valid, self.profile == profile, String(self.source) == source, resource == contact,
          self.messageID.isEmpty, self.topic.isEmpty, UUID(uuidString: messageID) != nil,
          GalaxySSILinkProtocol.validTopic(topic),
          (try? MqttRouteProtocol.integer(payload, "source_message_id")) == self.source,
          payload.string("type") == "text", payload.string("contact_id") == resource,
          payload.string("task_id") == task, payload.string("conversation_id") == conversation,
          payload.string("turn_id") == turn else { return nil }
    var copy = self; copy.messageID = messageID; copy.topic = topic; return copy
  }

  func matches(_ item: PendingLinkMessage, profile: String) -> Bool {
    valid && self.profile == profile && item.backgroundLearning == true &&
      UUID(uuidString: messageID) != nil && item.messageId == messageID &&
      GalaxySSILinkProtocol.validTopic(topic) && item.topic == topic &&
      item.clientSourceMessageId == String(source) && item.contactId == resource
  }

  func cognitionRequest(_ tasks: [GlobalCognitionTask], scope: GlobalBackgroundCognitionScope,
                        now: Int64) -> GalaxySSIGlobalCognitionDispatchRequest? {
    let owned = tasks.filter { $0.id == task }
    guard valid, kind == .cognition, now > 0, owned.count == 1, let current = owned.first,
          current.leaseExpiresAtMillis > now else { return nil }
    let request = GalaxySSIGlobalCognitionDispatchRequest(taskId: task, resourceId: resource, transport: transport,
      contactId: resource, sourceMessageId: source, conversationId: conversation, turnId: turn, systemPrompt: "", prompt: "")
    return scope.accepts(current, request: request) ? request : nil
  }

  func autonomousRequest(_ runs: [GlobalAutonomousRun], scope: GlobalRealtimePlanningScope,
                         now: Int64) -> GalaxySSIGlobalAutonomousDispatchRequest? {
    let owned = runs.filter { $0.id == task }
    guard valid, kind == .autonomous, now > 0, owned.count == 1, let run = owned.first,
          GlobalAutonomousSourceScope.allows(run, scope: scope) else { return nil }
    let response = AgentConnectorResponse(sourceMessageId: source, contactId: resource, content: "",
      conversationId: conversation, turnId: turn, taskId: task, receivedAtMillis: now)
    guard GlobalAutonomousSourceScope.matches(response, run: run) else { return nil }
    if action.isEmpty {
      guard run.status == .replanning, run.review.leaseExpiresAtMillis > now else { return nil }
    } else {
      let steps = run.actions.filter { $0.id == action && $0.status == .running && $0.sourceMessageId == source }
      guard run.status == .running, action == turn, steps.count == 1,
            steps[0].leaseExpiresAtMillis > now else { return nil }
    }
    return .init(runId: task, actionId: action, resourceId: resource, transport: transport, contactId: resource,
      sourceMessageId: source, conversationId: conversation, turnId: turn, systemPrompt: "", prompt: "")
  }

  func researchRequest(_ state: GlobalResearchExecutorState, scope: GlobalRealtimePlanningScope,
                       now: Int64) -> GlobalResearchDispatchRequest? {
    let requests = state.dispatchRequests.filter { $0.id == requestID }
    let tasks = state.tasks.filter { $0.id == task }
    guard valid, kind == .research, now > 0, requests.count == 1, let request = requests.first,
          tasks.count == 1, let current = tasks.first, current.status == .running,
          request.taskId == task, request.sourceMessageId == source, request.resourceId == resource,
          request.unitId == unit, request.stage == stage, request.leaseId == leaseID, request.ownerKey == requestOwner,
          request.contactId == resource, request.transport == transport,
          request.conversationId == conversation, request.turnId == turn,
          GlobalResearchSourceScope.allows(current, scope: scope),
          GlobalResearchSourceScope.allowsContext(request, scope: scope) else { return nil }
    switch request.stage {
    case .evidence:
      let units = current.researchPlan.units.filter { $0.id == request.unitId }
      guard current.researchPlan.phase == .collecting, units.count == 1, let unit = units.first, unit.status == .running,
            unit.sourceMessageId == source, unit.resourceId == resource, unit.leaseExpiresAtMillis > now else { return nil }
    case .synthesis:
      guard current.researchPlan.phase == .synthesizing, current.researchPlan.synthesisSourceMessageId == source,
            current.researchPlan.synthesisResourceId == resource,
            current.researchPlan.synthesisLeaseExpiresAtMillis > now else { return nil }
    }
    return request
  }

  @MainActor
  func permits(_ item: PendingLinkMessage, store: GalaxySSIStore, now: Int64) -> Bool {
    guard matches(item, profile: store.profile.identityFingerprint),
          let contact = store.contact(id: resource), !contact.deleted, contact.trustState == .verified,
          contact.deliveryMode.isGalaxySSILinkFamily,
          store.serverLinks.filter({ $0.paired && $0.routes.upTopic == topic &&
            (contact.desktopId.isBlank || $0.desktopId == contact.desktopId) }).count == 1 else { return false }
    let settings = store.globalAgentSettings
    switch kind {
    case .cognition:
      let ledger = GlobalAgentDeliberationStore(), tasks = ledger.cognitionTasks()
      let scope = GlobalBackgroundCognitionScope(enabled: settings.enabled && settings.modelUnderstandingEnabled,
        conversations: store.agentSessions(includeArchived: true))
      guard ledger.lastErrorDescription.isEmpty, let request = cognitionRequest(tasks, scope: scope, now: now) else { return false }
      return GalaxySSIGlobalAgentRuntimeBridge.permitsCognitionRequest(store: store, request: request, requireAvailable: false)
    case .autonomous:
      let ledger = GlobalAgentDeliberationStore(), runs = ledger.autonomousRuns()
      guard ledger.lastErrorDescription.isEmpty, let request = autonomousRequest(runs,
        scope: GlobalAutonomousSourceScope.liveScope(store), now: now) else { return false }
      return GalaxySSIGlobalAgentRuntimeBridge.permitsAutonomousRequest(store: store, request: request)
    case .research:
      let ledger = GalaxySSIGlobalResearchRuntimeStore(), state = ledger.state()
      let scope = GlobalRealtimePlanningScope(enabled: settings.enabled && settings.autonomousResearchEnabled,
        conversations: store.agentSessions(includeArchived: true))
      guard ledger.lastErrorDescription.isEmpty, let request = researchRequest(state, scope: scope, now: now) else { return false }
      return GalaxySSIGlobalAgentRuntimeBridge.permitsResearchRequest(store: store, request: request)
    }
  }
}

struct LinkOutboxReceiptWindow {
  private struct Entry {
    let topic: String
    let expiresAt: TimeInterval
  }

  private var entries: [String: Entry] = [:]

  func delay(topic: String, messageId: String, now: TimeInterval) -> TimeInterval {
    if let entry = entries[messageId], entry.expiresAt > now {
      return entry.expiresAt - now
    }
    let lane = entries.values.filter { $0.topic == topic && $0.expiresAt > now }
    guard lane.count >= 8, let first = lane.map(\.expiresAt).min() else { return 0 }
    return first - now
  }

  mutating func acquire(topic: String, messageId: String, now: TimeInterval) -> Bool {
    guard delay(topic: topic, messageId: messageId, now: now) == 0 else { return false }
    entries[messageId] = Entry(topic: topic, expiresAt: now + 30)
    return true
  }

  mutating func release(_ messageId: String) {
    entries.removeValue(forKey: messageId)
  }

  mutating func reconcile(now: TimeInterval, isPending: (String) -> Bool) {
    entries = entries.filter { $0.value.expiresAt > now && isPending($0.key) }
  }

  var messageIds: Set<String> { Set(entries.keys) }

  func nextExpiryDelay(now: TimeInterval) -> TimeInterval? {
    entries.values.map { max(0, $0.expiresAt - now) }.min()
  }
}

@MainActor
extension MessageCoordinator {
  func learningOutboxEligibility() -> (PendingLinkMessage) -> Bool {
    let enabled = store.globalAgentSettings.enabled
    if !enabled && pausedLegacyLearningSourceIDs == nil {
      pausedLegacyLearningSourceIDs = Set(backgroundLearningLeases().keys)
    }
    let legacy = pausedLegacyLearningSourceIDs ?? []
    return { AgentIOSCognitionSchedulePolicy.allowsTransport($0, learningEnabled: enabled, legacySources: legacy) }
  }

  private func backgroundLearningLeases() -> [String: Int64] {
    var leases: [String: Int64] = [:]
    func add(_ id: Int64, _ expires: Int64) {
      guard id > 0 else { return }
      let key = String(id)
      leases[key] = max(expires, leases[key] ?? 0)
    }
    let deliberation = GlobalAgentDeliberationStore()
    for task in deliberation.cognitionTasks() { add(task.sourceMessageId, task.leaseExpiresAtMillis) }
    for run in deliberation.autonomousRuns() {
      add(run.review.sourceMessageId, run.review.leaseExpiresAtMillis)
      for action in run.actions { add(action.sourceMessageId, action.leaseExpiresAtMillis) }
    }
    let research = GalaxySSIGlobalAgentRuntimeBridge.researchState()
    for task in research.tasks {
      add(task.sourceMessageId, task.leaseExpiresAtMillis)
      add(task.researchPlan.synthesisSourceMessageId, task.researchPlan.synthesisLeaseExpiresAtMillis)
      for unit in task.researchPlan.units { add(unit.sourceMessageId, unit.leaseExpiresAtMillis) }
    }
    return leases
  }

  private func flushPendingOutbox() async {
    guard usesLegacyMqtt, !Task.isCancelled else { return }
    guard !outboxFlushInProgress else {
      outboxFlushRequested = true
      return
    }
    outboxFlushInProgress = true
    defer {
      outboxFlushInProgress = false
      if outboxFlushRequested {
        outboxFlushRequested = false
        scheduleOutboxFlush(after: 0)
      } else if !Task.isCancelled {
        scheduleOutboxFlushFromStore()
      }
    }
    reconcileExhaustedPeerDeliveries()
    let discardedTransfers = attachmentTransferStore.prune()
    if !discardedTransfers.isEmpty {
      _ = deliveryStore.discardBlockedByAttachmentTransfers(discardedTransfers)
    }
    var activeMessageIds = await mqttClient.outstandingDurableMessageIds()
    guard !Task.isCancelled else { return }
    reconcileOutboxReceiptWindow()
    deliveryStore.holdStaleUnclassified(activeMessageIds: activeMessageIds.union(outboxReceiptWindow.messageIds))
    let eligible = learningOutboxEligibility()
    let heldFiles = deliveryStore.holdExhaustedAttachmentFiles(maxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts,
      active: activeMessageIds.union(outboxReceiptWindow.messageIds), eligible: eligible, canHold: { source, transfer in
        guard let file = attachmentTransferStore.find(transfer), file.scope.clientMessageId == source else { return false }
        return fileReceiptIsBound(file)
      })
    for id in heldFiles {
      if let file = attachmentTransferStore.find(id) { updateFileReceipt(file, state: .failed) }
    }
    handleExhaustedDeliveries(
      deliveryStore.discardExhausted(
        maxAttempts: Self.maximumOutboxDeliveryAttempts,
        attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts,
        activeMessageIds: activeMessageIds.union(outboxReceiptWindow.messageIds),
        eligible: eligible,
        peerBinding: { item in
          guard let source = UUID(uuidString: item.clientSourceMessageId.ifBlank(item.messageId)),
                let message = store.persistedMessage(id: source, contactId: item.contactId),
                message.isMine, !message.isSystem else { return nil }
          return peerDeliveryBinding(contactId: item.contactId, topic: item.topic)
        }
      )
    )
    reconcileExhaustedPeerDeliveries()
    let mediaProfile = mediaNetworkProfileProvider()
    let pending = deliveryStore.pending(
      allowValidatedNetworkMessages: mediaProfile.canUploadDeferredMedia,
      maxAttempts: Self.maximumOutboxDeliveryAttempts,
      attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts,
      eligible: eligible
    )
    guard !pending.isEmpty else { return }
    var rejectedSourceIds = Set<String>()
    for var item in pending {
      guard !Task.isCancelled else { return }
      if fileReadOutboxAllowed(item) == false {
        _ = deliveryStore.discardClientSourceMessage(item.clientSourceMessageId)
        continue
      }
      guard learningOutboxEligibility()(item) else { continue }
      if activeMessageIds.contains(item.messageId) || !deliveryStore.containsOutboxMessage(item.messageId) {
        continue
      }
      if let scope = item.learningScope,
         !scope.permits(item, store: store, now: GlobalRealtimeClock.nowMillis()) {
        deliveryStore.discard(messageId: item.messageId)
        continue
      }
      if item.clientSourceMessageId.hasPrefix(PublicAttentionResearchPolicy.outboxPrefix) {
        let source = Int64(item.clientSourceMessageId.dropFirst(PublicAttentionResearchPolicy.outboxPrefix.count))
        let research = GalaxySSIGlobalAgentRuntimeBridge.researchState()
        guard let source, let request = research.dispatchRequests.first(where: {
          $0.sourceMessageId == source && $0.contactId == item.contactId && $0.transport == .pairedAgent
        }), PublicAttentionResearchPolicy.allows(request, settings: store.globalAgentSettings),
           let contact = store.contact(id: item.contactId), publicAttentionLink(contact)?.routes.upTopic == item.topic,
           let task = research.task(id: request.taskId), task.leaseExpiresAtMillis > GlobalRealtimeClock.nowMillis()
        else {
          deliveryStore.discard(messageId: item.messageId)
          continue
        }
      } else if item.clientSourceMessageId.hasPrefix(PublicNewsPairedHeadlineBatch.outboxPrefix) {
        guard allowsPairedHeadlineDelivery(item) else {
          deliveryStore.discard(messageId: item.messageId)
          continue
        }
      } else if AgentIOSCognitionSchedulePolicy.isLearningTransport(item, legacySources: pausedLegacyLearningSourceIDs ?? []) {
        // Expired reservations belong to the learning journal, not transport replay.
        let expiry = backgroundLearningLeases()[item.clientSourceMessageId] ?? 0
        guard expiry > GlobalRealtimeClock.nowMillis(), item.learningScope != nil else {
          deliveryStore.discard(messageId: item.messageId)
          continue
        }
      }
      let sourceId = item.clientSourceMessageId.ifBlank(item.messageId)
      if GalaxySSIContactReminderOutbox.containsReminder(sourceId) {
        guard !GalaxySSIContactReminderOutbox.isExpired(sourceId, now: AgentControlPlaneClock.nowMillis()),
              let contact = store.contact(id: item.contactId), canSendContactReminder(to: contact) else {
          deliveryStore.discard(messageId: item.messageId)
          continue
        }
      }
      if rejectedSourceIds.contains(sourceId) { continue }
      if let deferred = item.deferredTaskPayload {
        guard deliveryStore.canPrepareDeferredTask(item),
              let link = store.serverLinks.first(where: { $0.paired && $0.routes.upTopic == item.topic }),
              let payload = (try? JSONSerialization.jsonObject(with: Data(deferred.utf8))) as? [String: Any],
              payload.string("message_id") == item.messageId,
              let wire = try? linkWirePayload(payload, link: link), wire.messageId == item.messageId,
              deliveryStore.commitDeferredTaskCiphertext(item, wirePayload: wire.wireText) else {
          deliveryStore.postponeDeferredTask(item)
          continue
        }
        item.wirePayload = wire.wireText
        item.deferredTaskPayload = nil
      }
      if let reason = GalaxySSIMqttWireChunking.permanentRejectionReason(
        wirePayload: item.wirePayload
      ) {
        rejectedSourceIds.insert(sourceId)
        _ = deliveryStore.discardClientSourceMessage(sourceId)
        handlePermanentlyRejectedDeliveries([
          PermanentlyRejectedLinkMessage(
            messageId: item.messageId,
            clientSourceMessageId: item.clientSourceMessageId,
            contactId: item.contactId,
            reason: reason
          )
        ])
        continue
      }
      reconcileOutboxReceiptWindow()
      guard outboxReceiptWindow.acquire(
        topic: item.topic, messageId: item.messageId, now: ProcessInfo.processInfo.systemUptime
      ) else { continue }
      let reservedAt = Date()
      deliveryStore.markAttempt(messageId: item.messageId, now: reservedAt)
      let result = await mqttClient.publishDurable(
        topic: item.topic,
        payload: Data(item.wirePayload.utf8),
        messageId: item.messageId
      ) { [weak self] persisted in
        Task { @MainActor [weak self] in
          guard let self else {
            persisted()
            return
          }
          self.deliveryStore.markPublished(messageId: item.messageId)
          self.scheduleOutboxFlushFromStore()
          persisted()
        }
      }
      if result.accepted {
        activeMessageIds.insert(item.messageId)
      } else if result == .deferred {
        outboxReceiptWindow.release(item.messageId)
        _ = deliveryStore.deferUnadmittedAttempt(messageId: item.messageId,
          reservedAttempts: item.attempts + 1, reservedAt: reservedAt)
      }
    }
  }

  private func reconcileOutboxReceiptWindow() {
    outboxReceiptWindow.reconcile(
      now: ProcessInfo.processInfo.systemUptime,
      isPending: deliveryStore.containsOutboxMessage
    )
  }

  func scheduleOutboxFlushFromStore() {
    guard usesLegacyMqtt else { return }
    let mediaProfile = mediaNetworkProfileProvider()
    let now = ProcessInfo.processInfo.systemUptime
    let receiptWindow = outboxReceiptWindow
    let eligible = learningOutboxEligibility()
    let receiptDelay: (PendingLinkMessage) -> TimeInterval = {
      receiptWindow.delay(topic: $0.topic, messageId: $0.messageId, now: now)
    }
    let retryDelay = deliveryStore.nextRetryDelay(
      allowValidatedNetworkMessages: mediaProfile.canUploadDeferredMedia,
      maxAttempts: Self.maximumOutboxDeliveryAttempts,
      attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts,
      eligible: eligible,
      minimumDelay: receiptDelay
    )
    let exhaustionDelay = deliveryStore.nextExhaustionDelay(maxAttempts: Self.maximumOutboxDeliveryAttempts,
      attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts, eligible: eligible, minimumDelay: receiptDelay)
    let projectionDelay: TimeInterval? = deliveryStore.pendingPeerFailures().isEmpty ? nil : 30
    if let delay = [retryDelay, exhaustionDelay, receiptWindow.nextExpiryDelay(now: now), projectionDelay].compactMap({ $0 }).min() {
      scheduleOutboxFlush(after: delay)
    }
  }

  func wakeOutboxAfterReceipt() {
    guard usesLegacyMqtt else { return }
    if outboxFlushInProgress {
      outboxFlushRequested = true
    } else {
      scheduleOutboxFlush(after: 0)
    }
  }

  private func peerDeliveryBinding(contactId: String, topic: String) -> String? {
    guard let contact = store.contact(id: contactId), contact.id == contactId, contact.isCommunicable else { return nil }
    let routes: GalaxySSILinkRoutes?
    if contact.isDesktopDeviceContact {
      routes = store.serverLinks.first { $0.paired && $0.desktopId == contact.desktopId && $0.routes.upTopic == topic }?.routes
    } else if contact.type.caseInsensitiveCompare("person") == .orderedSame, contact.desktopId.isBlank {
      routes = contact.opaquePhoneRoutes
    } else { return nil }
    guard let routes, routes.upTopic == topic else { return nil }
    return GalaxySSITransportReceiptJournal.binding(peerId: contactId, routes: routes)
  }

  private func reconcileExhaustedPeerDeliveries() {
    let resolved = deliveryStore.pendingPeerFailures().filter { failure in
      guard peerDeliveryBinding(contactId: failure.contactId, topic: failure.topic) == failure.binding,
            !deliveryStore.containsOutboxMessage(failure.messageId) else { return true }
      return store.persistExhaustedPeerDelivery(failure)
    }
    deliveryStore.retirePeerFailures(resolved)
  }

  func scheduleOutboxFlush(after delay: TimeInterval) {
    guard usesLegacyMqtt else { return }
    outboxRetryTask?.cancel()
    outboxRetryTask = Task { [weak self] in
      if delay > 0 {
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        catch { return }
      }
      guard !Task.isCancelled else { return }
      await self?.flushPendingOutbox()
    }
  }
}
