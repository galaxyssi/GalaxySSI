import Foundation

enum GalaxySSIContactReminderOutbox {
  private static let prefix = "peer-attention:"

  static func source(_ record: GalaxySSIContactReminder, action: GalaxySSIContactReminderAction) -> String {
    "\(prefix)\(record.expiresAt):\(record.id):\(action.rawValue)"
  }

  static func isExpired(_ source: String, now: Int64) -> Bool {
    guard containsReminder(source) else { return false }
    guard let deadline = source.dropFirst(prefix.count).split(separator: ":", maxSplits: 1).first
      .flatMap({ Int64($0) }) else { return true }
    return deadline <= now
  }

  static func containsReminder(_ source: String) -> Bool { source.hasPrefix(prefix) }

  static func failedRequestID(_ source: String) -> String? {
    guard containsReminder(source) else { return nil }
    let parts = source.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[2] == "request" else { return nil }
    return String(parts[1])
  }
}

@MainActor
extension MessageCoordinator {
  var contactReminderReceivingEnabled: Bool {
    get { store.defaults.object(forKey: contactReminderReceivingKey) as? Bool ?? true }
    set {
      store.defaults.set(newValue, forKey: contactReminderReceivingKey)
      if !newValue {
        contactReminderAlert.stop()
        contactReminders.filter { !$0.outgoing }.forEach { GalaxySSIContactReminderNotification.remove($0.id) }
      }
      objectWillChange.send()
    }
  }

  var contactReminderSoundInSilentMode: Bool {
    get { store.defaults.object(forKey: contactReminderReceivingKey + ".silent-mode-sound") as? Bool ?? true }
    set { store.defaults.set(newValue, forKey: contactReminderReceivingKey + ".silent-mode-sound") }
  }

  private var contactReminderReceivingKey: String {
    "galaxyssi.contact-reminders.enabled." + store.profile.identityFingerprint
  }

  private var contactReminderStore: GalaxySSIContactReminderStore {
    GalaxySSIContactReminderStore(defaults: store.defaults, secrets: store.secrets,
      owner: store.profile.identityFingerprint)
  }

  func canSendContactReminder(to contact: GalaxySSIContact) -> Bool {
    guard GalaxySSISignalEngine.isAvailable, contact.isCommunicable else { return false }
    if contact.isDesktopDeviceContact { return reminderLink(for: contact) != nil }
    return contact.type.lowercased() == "person" && contact.desktopId.isBlank &&
      !contact.galaxySSIId.isBlank && contact.opaquePhoneRoutes != nil
  }

  @discardableResult
  func sendContactReminder(to contact: GalaxySSIContact) -> Bool {
    guard let current = store.contact(id: contact.id), canSendContactReminder(to: current) else { return false }
    let now = AgentControlPlaneClock.nowMillis()
    do {
      let record = try contactReminderStore.create(peerID: current.id, now: now)
      syncContactReminderHistory(record, now: now)
      queueContactReminder(record, contact: current, now: now)
      if !current.isDesktopDeviceContact {
        Task { @MainActor [weak self] in await self?.recoverPhoneContactSessionIfNeeded(contactId: current.id) }
      }
      refreshContactReminderPresentation(now: now)
      outgoingContactReminderPanel = .init(owner: store.profile.identityFingerprint, id: record.id, peerID: record.peerID)
      return true
    } catch { return false }
  }

  @discardableResult
  func actOnContactReminder(id: String, action: GalaxySSIContactReminderAction) -> Bool {
    let now = AgentControlPlaneClock.nowMillis()
    guard let record = try? contactReminderStore.act(id: id, action: action, now: now) else { return false }
    if record.outgoing && action == .cancelled {
      deliveryStore.discard(messageId: contactReminderMessageID(record, action: .request))
    }
    syncContactReminderHistory(record, now: now)
    if let contact = store.contact(id: record.peerID) { queueContactReminder(record, contact: contact, now: now) }
    refreshContactReminderPresentation(now: now)
    return true
  }

  func receiveContactReminder(_ payload: [String: Any], authenticatedContact: GalaxySSIContact) -> Bool {
    let now = AgentControlPlaneClock.nowMillis()
    guard canSendContactReminder(to: authenticatedContact),
          let envelope = GalaxySSIContactReminderEnvelope(payload, now: now) else { return true }
    let accepted: GalaxySSIContactReminderStore.Acceptance?
    do {
      accepted = try contactReminderStore.receive(envelope, authenticatedPeer: authenticatedContact.id,
        enabled: contactReminderReceivingEnabled, quiet: contactReminderAlert.mustBeQuiet, now: now)
    } catch { return false }
    guard let accepted else { return true }
    syncContactReminderHistory(accepted.record, now: now)
    queueContactReminder(accepted.record, contact: authenticatedContact, now: now)
    refreshContactReminderPresentation(now: now)
    if accepted.shouldAlert {
      contactReminderAlert.show(accepted.record, language: store.languagePolicy.interfaceLanguage,
        audibleInSilentMode: contactReminderSoundInSilentMode)
    }
    return true
  }

  func restoreContactReminders() {
    let now = AgentControlPlaneClock.nowMillis()
    guard let records = try? contactReminderStore.records(now: now) else {
      contactReminders = []
      return
    }
    for record in records {
      guard let contact = store.contact(id: record.peerID), canSendContactReminder(to: contact) else { continue }
      syncContactReminderHistory(record, now: now)
      if record.pendingAction != nil { queueContactReminder(record, contact: contact, now: now) }
    }
    refreshContactReminderPresentation(now: now)
  }

  func handleContactReminderTransportFailure(source: String, contactID: String) -> Bool {
    guard GalaxySSIContactReminderOutbox.containsReminder(source) else { return false }
    let now = AgentControlPlaneClock.nowMillis()
    if let id = GalaxySSIContactReminderOutbox.failedRequestID(source),
       let record = try? contactReminderStore.failRequest(id: id, peerID: contactID, now: now) {
      syncContactReminderHistory(record, now: now)
      refreshContactReminderPresentation(now: now)
    }
    return true
  }

  private func refreshContactReminderPresentation(now: Int64) {
    contactReminderExpiryTask?.cancel()
    contactReminderExpiryTask = nil
    let previous = contactReminders
    contactReminders = (try? contactReminderStore.records(now: now)) ?? []
    if let selection = outgoingContactReminderPanel,
       selection.resolve(in: contactReminders, owner: store.profile.identityFingerprint, now: now) == nil {
      outgoingContactReminderPanel = nil
    }
    let presentableIDs = Set(contactReminders.filter { !$0.outgoing && !$0.status.terminal && $0.status != .muted }.map(\.id))
    for record in previous where !record.outgoing && !presentableIDs.contains(record.id) {
      GalaxySSIContactReminderNotification.remove(record.id)
    }
    contactReminderAlert.reconcile(contactReminders)
    guard let next = contactReminders.filter({ !$0.status.terminal }).map(\.expiresAt).min() else { return }
    let interval = max(1, min(next - now, GalaxySSIContactReminderEnvelope.lifetime))
    contactReminderExpiryTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000) }
      catch { return }
      self?.restoreContactReminders()
    }
  }

  private func reminderLink(for contact: GalaxySSIContact) -> ServerLink? {
    store.serverLinks.first { $0.paired && $0.desktopId == contact.desktopId }
  }

  private func contactReminderMessageID(
    _ record: GalaxySSIContactReminder, action: GalaxySSIContactReminderAction
  ) -> String {
    GalaxySSILinkProtocol.normalizedMessageId(AgentTaskIdentityPolicy.taskId(ownerId: store.profile.galaxySSIId,
      contactId: record.peerID, sourceMessageId: "\(record.id):\(action.rawValue)",
      conversationId: "peer-attention", turnId: String(record.createdAt)))
  }

  private func queueContactReminder(_ record: GalaxySSIContactReminder, contact: GalaxySSIContact, now: Int64) {
    guard let action = record.pendingAction, contact.id == record.peerID,
          canSendContactReminder(to: contact), record.expiresAt > now else { return }
    let messageID = contactReminderMessageID(record, action: action)
    let sender = signalEngine.identity.name
    let recipient = contact.isDesktopDeviceContact ? contact.desktopId : sender
    var payload = record.envelope(action).payload(messageId: messageID, recipient: recipient, sender: sender, now: now)
    let topic: String
    let wire: String
    if contact.isDesktopDeviceContact {
      guard let link = reminderLink(for: contact), signalEngine.hasSession(remoteName: link.desktopId) else { return }
      payload["client_route_id"] = link.routes.clientRouteId
      payload["desktop_id"] = link.desktopId
      guard let encoded = try? linkWirePayload(payload, link: link), encoded.messageId == messageID else { return }
      topic = link.routes.upTopic
      wire = encoded.wireText
    } else {
      guard let routes = contact.opaquePhoneRoutes, signalEngine.hasSession(remoteName: contact.galaxySSIId),
            let encoded = try? phoneContactWirePayload(payload, contact: contact), encoded.messageId == messageID
      else { return }
      topic = routes.upTopic
      wire = encoded.wireText
    }
    let request = LinkDeliveryEnqueueRequest(messageId: messageID, topic: topic, wirePayload: wire,
      requiresValidatedNetwork: false, blockedByAttachmentTransferIds: [],
      clientSourceMessageId: GalaxySSIContactReminderOutbox.source(record, action: action), contactId: contact.id)
    guard deliveryStore.enqueueContactReminder(request) else { return }
    try? contactReminderStore.markQueued(id: record.id, action: action, now: now)
    scheduleOutboxFlushFromStore()
  }

  private func syncContactReminderHistory(_ record: GalaxySSIContactReminder, now: Int64) {
    guard let id = record.historyID else { return }
    let previous = store.persistedMessage(id: id, contactId: record.peerID)
    guard previous != nil || record.historyPublished != true else { return }
    let language = store.languagePolicy.interfaceLanguage
    let title = GalaxySSILocalization.string(record.outgoing ? "galaxyssi.contact_reminder.sent" : "galaxyssi.contact_reminder.received",
      fallback: record.outgoing ? "Contact reminder sent" : "Contact reminder received", language: language)
    let status = GalaxySSILocalization.string(record.status.localizationKey, fallback: record.status.defaultTitle, language: language)
    let content = title + "\n" + status
    if previous?.content == content {
      if record.historyPublished != true { try? contactReminderStore.markHistoryPublished(id: record.id, now: now) }
      return
    }
    var message = previous ?? ChatMessage(id: id, contactId: record.peerID, content: content, isMine: record.outgoing,
      createdAt: Date(timeIntervalSince1970: Double(record.createdAt) / 1_000), deliveryStatus: .local,
      conversationId: store.activeConversationId(for: record.peerID), turnId: "reminder:" + record.id,
      remoteMessageId: "reminder:" + record.id)
    message.content = content
    guard store.chatHistoryDatabase.upsert(message) else { return }
    var messages = store.messagesByContact[record.peerID] ?? []
    if let index = messages.firstIndex(where: { $0.id == id }) { messages[index] = message }
    else { messages.append(message) }
    store.messagesByContact[record.peerID] = messages.sorted { $0.createdAt < $1.createdAt }
    try? contactReminderStore.markHistoryPublished(id: record.id, now: now)
  }
}

extension GalaxySSIContactReminderStatus {
  var localizationKey: String { "galaxyssi.contact_reminder.status." + rawValue }

  var defaultTitle: String {
    switch self {
    case .queued: return "Waiting for delivery"
    case .received: return "Delivered"
    case .quiet: return "Delivered quietly"
    case .muted: return "Muted"
    case .acknowledged: return "Acknowledged"
    case .dismissed: return "Ignored"
    case .cancelled: return "Cancelled"
    case .disabled: return "Reminders disabled by recipient"
    case .expired: return "Expired"
    case .failed: return "Could not send"
    }
  }
}
