import CryptoKit
import Foundation

struct PendingLinkMessage: Codable, Equatable, Identifiable {
  var id: String { messageId }
  var messageId: String
  var topic: String
  var wirePayload: String
  var wirePayloadFile: String?
  var status: String
  var attempts: Int
  var nextAttemptAt: Date
  var createdAt: Date
  var updatedAt: Date
  var requiresValidatedNetwork: Bool
  var blockedByAttachmentTransferIds: [String]
  var clientSourceMessageId: String
  var contactId: String

  init(
    messageId: String,
    topic: String,
    wirePayload: String,
    wirePayloadFile: String? = nil,
    status: String,
    attempts: Int,
    nextAttemptAt: Date,
    createdAt: Date,
    updatedAt: Date,
    requiresValidatedNetwork: Bool = false,
    blockedByAttachmentTransferIds: [String] = [],
    clientSourceMessageId: String = "",
    contactId: String = ""
  ) {
    self.messageId = messageId
    self.topic = topic
    self.wirePayload = wirePayload
    self.wirePayloadFile = wirePayloadFile
    self.status = status
    self.attempts = attempts
    self.nextAttemptAt = nextAttemptAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.requiresValidatedNetwork = requiresValidatedNetwork
    self.blockedByAttachmentTransferIds = Self.normalizedTransferIds(blockedByAttachmentTransferIds)
    self.clientSourceMessageId = clientSourceMessageId
    self.contactId = contactId
  }

  enum CodingKeys: String, CodingKey {
    case messageId
    case topic
    case wirePayload
    case wirePayloadFile = "wire_payload_file"
    case status
    case attempts
    case nextAttemptAt
    case createdAt
    case updatedAt
    case requiresValidatedNetwork = "requires_validated_network"
    case blockedByAttachmentTransferIds = "blocked_by_attachment_transfers"
    case clientSourceMessageId = "client_source_message_id"
    case contactId = "contact_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    messageId = try container.decode(String.self, forKey: .messageId)
    topic = try container.decode(String.self, forKey: .topic)
    wirePayload = try container.decodeIfPresent(String.self, forKey: .wirePayload) ?? ""
    wirePayloadFile = try container.decodeIfPresent(String.self, forKey: .wirePayloadFile)
    status = try container.decode(String.self, forKey: .status)
    attempts = try container.decode(Int.self, forKey: .attempts)
    nextAttemptAt = try container.decode(Date.self, forKey: .nextAttemptAt)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    requiresValidatedNetwork = try container.decodeIfPresent(
      Bool.self,
      forKey: .requiresValidatedNetwork
    ) ?? false
    blockedByAttachmentTransferIds = Self.normalizedTransferIds(
      try container.decodeIfPresent([String].self, forKey: .blockedByAttachmentTransferIds) ?? []
    )
    clientSourceMessageId = try container.decodeIfPresent(String.self, forKey: .clientSourceMessageId) ?? ""
    contactId = try container.decodeIfPresent(String.self, forKey: .contactId) ?? ""
  }

  static func normalizedTransferIds(_ transferIds: [String]) -> [String] {
    var seen = Set<String>()
    return transferIds.compactMap { transferId in
      let clean = transferId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard clean.range(of: transferIdPattern, options: .regularExpression) != nil,
            seen.insert(clean).inserted else {
        return nil
      }
      return clean
    }
  }

  private static let transferIdPattern = #"^[a-f0-9]{64}$"#
}

struct LinkDeliveryEnqueueRequest: Equatable {
  var messageId: String
  var topic: String
  var wirePayload: String
  var requiresValidatedNetwork: Bool
  var blockedByAttachmentTransferIds: [String]
  var clientSourceMessageId: String
  var contactId: String
  var recoverableEnvelope: String = ""
}

struct PendingIncomingLinkMessage: Codable, Equatable, Identifiable {
  var id: String { messageId }
  var messageId: String
  var payload: String
  var createdAt: Date
}

struct KnownLinkCiphertext: Codable, Equatable {
  var messageId: String
  var receiptRequired: Bool
  var createdAt: Date
}

enum IncomingStageResult: Equatable {
  case staged
  case pending
  case completed
  case invalid
}

struct ExhaustedLinkMessage: Equatable, Identifiable {
  var id: String { messageId }
  var messageId: String
  var clientSourceMessageId: String
  var contactId: String
  var attempts: Int
}

struct PermanentlyRejectedLinkMessage: Equatable, Identifiable {
  var id: String { messageId }
  var messageId: String
  var clientSourceMessageId: String
  var contactId: String
  var reason: String
}

struct AttachmentDependencyRelease: Equatable {
  var matchedMessages: Int
  var releasedMessages: Int
}

final class GalaxySSILinkRecoveryEnvelopeStore {
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let storageKey: String
  private var values: [String: String]

  init(
    defaults: UserDefaults,
    secrets: GalaxySSISecretStore,
    storageKey: String = "galaxyssi-ios-link-peer-recovery-v1"
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.storageKey = storageKey
    if let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    ), let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
      values = decoded
    } else {
      values = [:]
    }
  }

  func value(messageId: String) -> String {
    values[messageId] ?? ""
  }

  func set(_ value: String, messageId: String) {
    guard !messageId.isEmpty, !value.isEmpty else { return }
    values[messageId] = value
    persist()
  }

  func remove(messageId: String) {
    guard values.removeValue(forKey: messageId) != nil else { return }
    persist()
  }

  func clear() {
    values.removeAll()
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  private func persist() {
    guard !values.isEmpty else {
      GalaxySSIEncryptedUserDefaultsStore.destroy(
        defaults: defaults,
        key: storageKey,
        secrets: secrets
      )
      return
    }
    guard let data = try? JSONEncoder().encode(values) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }
}

@MainActor
final class GalaxySSILinkDeliveryStore {
  private struct PersistedState: Codable {
    var transportEpoch: String
    var outbox: [PendingLinkMessage]
    var completedInboxIds: [String]
    var pendingIncoming: [String: PendingIncomingLinkMessage]
    var ciphertextBindings: [String: KnownLinkCiphertext]
  }

  private let defaults: UserDefaults
  private let payloadStore: GalaxySSILinkOutboxPayloadStore
  private let recoveryStore: GalaxySSILinkRecoveryEnvelopeStore
  private let storageKey = "galaxyssi-ios-link-delivery-v1"
  private let maximumInboxIds = 4096
  private let maximumPendingIncoming = 256
  private let maximumCiphertextBindings = 4096
  private let maximumPendingAge: TimeInterval = 7 * 24 * 60 * 60
  private static let maximumRecoverableEnvelopeBytes = 64 * 1024

  private var state: PersistedState

  init(
    defaults: UserDefaults = .standard,
    payloadStore: GalaxySSILinkOutboxPayloadStore = GalaxySSILinkOutboxPayloadStore(),
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.payloadStore = payloadStore
    recoveryStore = GalaxySSILinkRecoveryEnvelopeStore(defaults: defaults, secrets: secrets)
    if let data = defaults.data(forKey: storageKey),
       let saved = try? JSONDecoder.linkReliability.decode(PersistedState.self, from: data) {
      state = saved
    } else {
      state = PersistedState(
        transportEpoch: "",
        outbox: [],
        completedInboxIds: [],
        pendingIncoming: [:],
        ciphertextBindings: [:]
      )
      save()
    }
  }

  @discardableResult
  func ensureTransportEpoch(_ epoch: String) -> Bool {
    precondition(!epoch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    guard state.transportEpoch != epoch else { return false }
    state.transportEpoch = epoch
    state.outbox.forEach(deleteWirePayload)
    state.outbox.removeAll()
    payloadStore.clear()
    recoveryStore.clear()
    save()
    return true
  }

  func enqueue(
    messageId: String,
    topic: String,
    wirePayload: String,
    requiresValidatedNetwork: Bool = false,
    blockedByAttachmentTransferIds: [String] = [],
    clientSourceMessageId: String = "",
    contactId: String = "",
    recoverableEnvelope: String = "",
    now: Date = Date()
  ) {
    enqueueBatch(
      [
        LinkDeliveryEnqueueRequest(
          messageId: messageId,
          topic: topic,
          wirePayload: wirePayload,
          requiresValidatedNetwork: requiresValidatedNetwork,
          blockedByAttachmentTransferIds: blockedByAttachmentTransferIds,
          clientSourceMessageId: clientSourceMessageId,
          contactId: contactId,
          recoverableEnvelope: recoverableEnvelope
        )
      ],
      now: now
    )
  }

  func enqueueBatch(_ requests: [LinkDeliveryEnqueueRequest], now: Date = Date()) {
    guard !requests.isEmpty else { return }
    var changed = false
    var existingMessageIds = Set(state.outbox.map(\.messageId))
    for request in requests {
      guard !request.messageId.isEmpty,
            !request.topic.isEmpty,
            !request.wirePayload.isEmpty,
            existingMessageIds.insert(request.messageId).inserted else {
        continue
      }
      let transferDependencies = PendingLinkMessage.normalizedTransferIds(
        request.blockedByAttachmentTransferIds
      )
      let wireReference = payloadStore.reference(
        messageId: request.messageId,
        wirePayload: request.wirePayload
      )
      state.outbox.append(
        PendingLinkMessage(
          messageId: request.messageId,
          topic: request.topic,
          wirePayload: wireReference.wirePayload,
          wirePayloadFile: wireReference.wirePayloadFile,
          status: "queued",
          attempts: 0,
          nextAttemptAt: now,
          createdAt: now,
          updatedAt: now,
          requiresValidatedNetwork: request.requiresValidatedNetwork,
          blockedByAttachmentTransferIds: transferDependencies,
          clientSourceMessageId: request.clientSourceMessageId,
          contactId: request.contactId
        )
      )
      if Data(request.recoverableEnvelope.utf8).count <= Self.maximumRecoverableEnvelopeBytes {
        recoveryStore.set(request.recoverableEnvelope, messageId: request.messageId)
      }
      changed = true
    }
    if changed { save() }
  }

  static func recoverablePeerEnvelope(
    payload: [String: Any],
    applicationEnvelope: [String: Any],
    isDirectPhoneContact: Bool
  ) -> String {
    guard isDirectPhoneContact,
          payload.string("type") == "peer_message",
          let data = try? JSONSerialization.data(
            withJSONObject: applicationEnvelope,
            options: [.sortedKeys]
          ),
          data.count <= maximumRecoverableEnvelopeBytes else {
      return ""
    }
    return String(decoding: data, as: UTF8.self)
  }

  @discardableResult
  func reencryptRecoverableMessages(
    contactId: String,
    topic: String,
    now: Date = Date(),
    encrypt: ([String: Any]) -> String?
  ) -> Int {
    let cleanContactId = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanContactId.isEmpty, !cleanTopic.isEmpty else { return 0 }
    var changed = 0
    for index in state.outbox.indices where state.outbox[index].contactId == cleanContactId {
      let messageId = state.outbox[index].messageId
      let encoded = recoveryStore.value(messageId: messageId)
      guard let data = encoded.data(using: .utf8),
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let wirePayload = encrypt(envelope),
            !wirePayload.isEmpty else {
        continue
      }
      deleteWirePayload(state.outbox[index])
      let reference = payloadStore.reference(messageId: messageId, wirePayload: wirePayload)
      state.outbox[index].topic = cleanTopic
      state.outbox[index].wirePayload = reference.wirePayload
      state.outbox[index].wirePayloadFile = reference.wirePayloadFile
      state.outbox[index].status = "queued"
      state.outbox[index].attempts = 0
      state.outbox[index].nextAttemptAt = now
      state.outbox[index].updatedAt = now
      changed += 1
    }
    if changed > 0 { save() }
    return changed
  }

  func markAttempt(messageId: String, now: Date = Date()) {
    updateOutbox(messageId: messageId) { item in
      item.attempts += 1
      item.status = "publishing"
      item.nextAttemptAt = now.addingTimeInterval(GalaxySSILinkRetryPolicy.delaySeconds(attempt: item.attempts))
      item.updatedAt = now
    }
  }

  func markPublished(messageId: String, now: Date = Date()) {
    updateOutbox(messageId: messageId) { item in
      let attempts = max(item.attempts, 1)
      item.status = "published"
      item.nextAttemptAt = now.addingTimeInterval(GalaxySSILinkRetryPolicy.delaySeconds(attempt: attempts))
      item.updatedAt = now
    }
  }

  func acknowledge(messageId: String) {
    discard(messageId: messageId)
  }

  func discard(messageId: String) {
    guard !messageId.isEmpty else { return }
    let before = state.outbox.count
    state.outbox
      .filter { $0.messageId == messageId }
      .forEach(deleteOutboxPayload)
    state.outbox.removeAll { $0.messageId == messageId }
    if state.outbox.count != before {
      save()
    }
  }

  @discardableResult
  func discardClientSourceMessage(_ sourceMessageId: String) -> Int {
    guard !sourceMessageId.isEmpty else { return 0 }
    let before = state.outbox.count
    state.outbox
      .filter { $0.clientSourceMessageId == sourceMessageId || $0.messageId == sourceMessageId }
      .forEach(deleteOutboxPayload)
    state.outbox.removeAll {
      $0.clientSourceMessageId == sourceMessageId || $0.messageId == sourceMessageId
    }
    let removed = before - state.outbox.count
    if removed > 0 { save() }
    return removed
  }

  @discardableResult
  func discardExhausted(maxAttempts: Int) -> [ExhaustedLinkMessage] {
    guard maxAttempts > 0 else { return [] }
    let source = state.outbox
    var kept: [PendingLinkMessage] = []
    var exhausted: [ExhaustedLinkMessage] = []
    for item in source {
      guard item.attempts >= maxAttempts else {
        kept.append(item)
        continue
      }
      deleteOutboxPayload(item)
      exhausted.append(
        ExhaustedLinkMessage(
          messageId: item.messageId,
          clientSourceMessageId: item.clientSourceMessageId,
          contactId: item.contactId,
          attempts: item.attempts
        )
      )
    }
    guard exhausted.isEmpty == false else { return [] }
    state.outbox = kept
    save()
    return exhausted
  }

  @discardableResult
  func recoverInterruptedPublishing() -> [ExhaustedLinkMessage] {
    let interruptedStatuses: Set<String> = ["preparing", "publishing", "sending"]
    let interrupted = state.outbox.filter { interruptedStatuses.contains($0.status) }
    guard !interrupted.isEmpty else { return [] }
    interrupted.forEach(deleteOutboxPayload)
    state.outbox.removeAll { interruptedStatuses.contains($0.status) }
    save()
    return interrupted.map {
      ExhaustedLinkMessage(
        messageId: $0.messageId,
        clientSourceMessageId: $0.clientSourceMessageId,
        contactId: $0.contactId,
        attempts: $0.attempts
      )
    }
  }

  func pending(
    now: Date = Date(),
    allowValidatedNetworkMessages: Bool = true,
    maxAttempts: Int = Int.max
  ) -> [PendingLinkMessage] {
    let ready = state.outbox
      .compactMap { item -> PendingLinkMessage? in
        if !item.blockedByAttachmentTransferIds.isEmpty {
          return nil
        }
        if item.requiresValidatedNetwork && !allowValidatedNetworkMessages {
          return nil
        }
        if item.attempts >= maxAttempts {
          return nil
        }
        guard item.nextAttemptAt <= now,
              let resolved = resolvedMessage(item) else {
          return nil
        }
        return resolved
      }
      .sorted { left, right in
        if left.nextAttemptAt == right.nextAttemptAt {
          return left.createdAt < right.createdAt
        }
        return left.nextAttemptAt < right.nextAttemptAt
      }
    var routeQueues: [String: [PendingLinkMessage]] = [:]
    var activeRoutes: [String] = []
    for item in ready {
      let route = Self.routeScope(item.topic)
      if routeQueues[route] == nil {
        routeQueues[route] = []
        activeRoutes.append(route)
      }
      routeQueues[route, default: []].append(item)
    }
    var result: [PendingLinkMessage] = []
    while !activeRoutes.isEmpty {
      let route = activeRoutes.removeFirst()
      guard var queue = routeQueues[route], !queue.isEmpty else { continue }
      result.append(queue.removeFirst())
      if !queue.isEmpty {
        activeRoutes.append(route)
      }
      routeQueues[route] = queue
    }
    return result
  }

  func nextRetryDelay(
    now: Date = Date(),
    allowValidatedNetworkMessages: Bool = true,
    maxAttempts: Int = Int.max
  ) -> TimeInterval? {
    state.outbox
      .filter { item in
        item.blockedByAttachmentTransferIds.isEmpty &&
          hasWirePayload(item) &&
          item.attempts < maxAttempts &&
          !(item.requiresValidatedNetwork && !allowValidatedNetworkMessages)
      }
      .map { max(0, $0.nextAttemptAt.timeIntervalSince(now)) }
      .min()
  }

  func makePendingImmediatelyRetryable(now: Date = Date()) {
    var changed = false
    for index in state.outbox.indices where state.outbox[index].nextAttemptAt > now {
      state.outbox[index].status = "queued"
      state.outbox[index].nextAttemptAt = now
      state.outbox[index].updatedAt = now
      changed = true
    }
    if changed { save() }
  }

  func discardRoutes(_ routes: GalaxySSILinkRoutes) -> Int {
    let topics = routes.sendWindow.union(routes.receiveWindow)
    let before = state.outbox.count
    state.outbox
      .filter { topics.contains($0.topic) }
      .forEach(deleteOutboxPayload)
    state.outbox.removeAll { topics.contains($0.topic) }
    let removed = before - state.outbox.count
    if removed > 0 { save() }
    return removed
  }

  @discardableResult
  func releaseAttachmentDependency(_ transferId: String, now: Date = Date()) -> Int {
    releaseAttachmentDependencyResult(transferId, now: now).releasedMessages
  }

  @discardableResult
  func releaseAttachmentDependencyResult(
    _ transferId: String,
    now: Date = Date()
  ) -> AttachmentDependencyRelease {
    guard let normalized = PendingLinkMessage.normalizedTransferIds([transferId]).first else {
      return AttachmentDependencyRelease(matchedMessages: 0, releasedMessages: 0)
    }
    var changed = false
    var matched = 0
    var released = 0
    for index in state.outbox.indices {
      let before = state.outbox[index].blockedByAttachmentTransferIds.count
      state.outbox[index].blockedByAttachmentTransferIds.removeAll { $0 == normalized }
      guard state.outbox[index].blockedByAttachmentTransferIds.count != before else {
        continue
      }
      matched += 1
      changed = true
      state.outbox[index].updatedAt = now
      if state.outbox[index].blockedByAttachmentTransferIds.isEmpty {
        released += 1
        state.outbox[index].status = "queued"
        state.outbox[index].nextAttemptAt = now
      }
    }
    if changed { save() }
    return AttachmentDependencyRelease(matchedMessages: matched, releasedMessages: released)
  }

  @discardableResult
  func discardBlockedByAttachmentTransfers(_ transferIds: [String]) -> Int {
    let normalized = Set(PendingLinkMessage.normalizedTransferIds(transferIds))
    guard !normalized.isEmpty else { return 0 }
    let before = state.outbox.count
    state.outbox
      .filter { item in
        !Set(item.blockedByAttachmentTransferIds).isDisjoint(with: normalized)
      }
      .forEach(deleteOutboxPayload)
    state.outbox.removeAll { item in
      !Set(item.blockedByAttachmentTransferIds).isDisjoint(with: normalized)
    }
    let removed = before - state.outbox.count
    if removed > 0 { save() }
    return removed
  }

  func claimIncoming(messageId: String) -> Bool {
    guard !messageId.isEmpty else { return false }
    guard !state.completedInboxIds.contains(messageId) else { return false }
    state.completedInboxIds.append(messageId)
    trimInbox()
    save()
    return true
  }

  func stageIncoming(messageId: String, payload: String, now: Date = Date()) -> IncomingStageResult {
    guard !messageId.isEmpty, !payload.isEmpty else { return .invalid }
    prune(now: now)
    if state.completedInboxIds.contains(messageId) {
      return .completed
    }
    if state.pendingIncoming[messageId] != nil {
      return .pending
    }
    state.pendingIncoming[messageId] = PendingIncomingLinkMessage(
      messageId: messageId,
      payload: payload,
      createdAt: now
    )
    trimPendingIncoming()
    save()
    return .staged
  }

  func pendingIncoming(now: Date = Date()) -> [PendingIncomingLinkMessage] {
    prune(now: now)
    return state.pendingIncoming.values.sorted { $0.createdAt < $1.createdAt }
  }

  func completeIncoming(messageId: String) {
    guard !messageId.isEmpty else { return }
    state.pendingIncoming.removeValue(forKey: messageId)
    if !state.completedInboxIds.contains(messageId) {
      state.completedInboxIds.append(messageId)
      trimInbox()
    }
    save()
  }

  func bindCiphertext(digest: String, messageId: String, receiptRequired: Bool, now: Date = Date()) throws {
    guard !digest.isEmpty, !messageId.isEmpty else { return }
    if let existing = state.ciphertextBindings[digest],
       existing.messageId != messageId {
      throw GalaxySSIError.invalidPayload("ciphertext is already bound to another message.")
    }
    state.ciphertextBindings[digest] = KnownLinkCiphertext(
      messageId: messageId,
      receiptRequired: receiptRequired,
      createdAt: state.ciphertextBindings[digest]?.createdAt ?? now
    )
    trimCiphertextBindings(now: now)
    save()
  }

  func messageForCiphertext(digest: String, now: Date = Date()) -> KnownLinkCiphertext? {
    prune(now: now)
    return state.ciphertextBindings[digest]
  }

  func clear() {
    state.outbox.forEach(deleteWirePayload)
    state = PersistedState(
      transportEpoch: "",
      outbox: [],
      completedInboxIds: [],
      pendingIncoming: [:],
      ciphertextBindings: [:]
    )
    payloadStore.clear()
    recoveryStore.clear()
    save()
  }

  private func resolvedMessage(_ item: PendingLinkMessage) -> PendingLinkMessage? {
    let wirePayload = payloadStore.resolve(
      inline: item.wirePayload,
      fileName: item.wirePayloadFile
    )
    guard !wirePayload.isEmpty else { return nil }
    var resolved = item
    resolved.wirePayload = wirePayload
    return resolved
  }

  private func hasWirePayload(_ item: PendingLinkMessage) -> Bool {
    !payloadStore.resolve(
      inline: item.wirePayload,
      fileName: item.wirePayloadFile
    ).isEmpty
  }

  private static func routeScope(_ topic: String) -> String {
    let segments = topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard segments.count >= 5, segments[0] == "galaxyssichat" else {
      return topic
    }
    return "\(segments[2])/\(segments[3])"
  }

  private func deleteWirePayload(_ item: PendingLinkMessage) {
    payloadStore.delete(fileName: item.wirePayloadFile)
  }

  private func deleteOutboxPayload(_ item: PendingLinkMessage) {
    deleteWirePayload(item)
    recoveryStore.remove(messageId: item.messageId)
  }

  private func updateOutbox(messageId: String, mutate: (inout PendingLinkMessage) -> Void) {
    guard let index = state.outbox.firstIndex(where: { $0.messageId == messageId }) else { return }
    mutate(&state.outbox[index])
    save()
  }

  private func prune(now: Date) {
    let cutoff = now.addingTimeInterval(-maximumPendingAge)
    let originalPending = state.pendingIncoming.count
    let originalCiphertext = state.ciphertextBindings.count
    state.pendingIncoming = state.pendingIncoming.filter { $0.value.createdAt >= cutoff }
    state.ciphertextBindings = state.ciphertextBindings.filter { $0.value.createdAt >= cutoff }
    trimPendingIncoming()
    trimCiphertextBindings(now: now)
    if state.pendingIncoming.count != originalPending ||
      state.ciphertextBindings.count != originalCiphertext {
      save()
    }
  }

  private func trimInbox() {
    if state.completedInboxIds.count > maximumInboxIds {
      state.completedInboxIds = Array(state.completedInboxIds.suffix(maximumInboxIds))
    }
  }

  private func trimPendingIncoming() {
    guard state.pendingIncoming.count > maximumPendingIncoming else { return }
    let keep = state.pendingIncoming.values
      .sorted { $0.createdAt > $1.createdAt }
      .prefix(maximumPendingIncoming)
    state.pendingIncoming = Dictionary(uniqueKeysWithValues: keep.map { ($0.messageId, $0) })
  }

  private func trimCiphertextBindings(now: Date) {
    let cutoff = now.addingTimeInterval(-maximumPendingAge)
    let kept = state.ciphertextBindings
      .filter { $0.value.createdAt >= cutoff }
      .sorted { $0.value.createdAt > $1.value.createdAt }
      .prefix(maximumCiphertextBindings)
    state.ciphertextBindings = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
  }

  private func save() {
    if let data = try? JSONEncoder.linkReliability.encode(state) {
      defaults.set(data, forKey: storageKey)
    }
  }
}

enum GalaxySSILinkDeliveryAckPolicy {
  static func transportMessageId(payload: [String: Any]) -> String {
    if isUUID(payload.string("transport_message_id")) {
      return payload.string("transport_message_id")
    }
    if isUUID(payload.string("source_message_id")) {
      return payload.string("source_message_id")
    }
    if isUUID(payload.string("reply_to")) {
      return payload.string("reply_to")
    }
    return ""
  }

  static func clientSourceMessageId(payload: [String: Any]) -> String {
    let explicit = payload.string("client_source_message_id")
    if !explicit.isEmpty { return explicit }
    let source = payload.string("source_message_id")
    return isUUID(source) ? "" : source
  }

  private static func isUUID(_ value: String) -> Bool {
    !value.isEmpty && UUID(uuidString: value) != nil
  }
}

enum GalaxySSITransportPrivacyPolicy {
  private static let localOnlyTypePrefixes = [
    "evolution_",
    "self_evolution",
    "memory_evolution",
    "global_agent",
    "global_memory",
    "global_cognition",
    "global_research"
  ]

  private static let localOnlyConversationPrefixes = [
    "global-cognition:",
    "global-research:",
    "global-run:",
    "global-replan:",
    "global-autonomous:",
    "global-autonomous-review:",
    "self-evolution:",
    "memory-evolution:"
  ]

  private static let delegatableBackgroundConversationPrefixes = [
    "global-cognition:",
    "global-research:",
    "global-run:",
    "global-replan:",
    "global-autonomous:",
    "global-autonomous-review:"
  ]

  static func isLocalOnly(
    _ payload: [String: Any],
    trustedBackgroundCognitionAuthorized: Bool = false
  ) -> Bool {
    let type = payload.string("type").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let conversationId = payload.string("conversation_id")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if trustedBackgroundCognitionAuthorized,
       type == "text",
       delegatableBackgroundConversationPrefixes.contains(where: { conversationId.hasPrefix($0) }) {
      return false
    }
    if localOnlyTypePrefixes.contains(where: { type.hasPrefix($0) }) {
      return true
    }
    if localOnlyConversationPrefixes.contains(where: { conversationId.hasPrefix($0) }) {
      return true
    }
    let taskKind = payload.string("task_kind")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return ["self_evolution", "memory_evolution", "global_agent"].contains(taskKind)
  }
}

enum GalaxySSILinkCiphertextReplayPolicy {
  private static let encryptedFields = [
    "scheme",
    "from",
    "to",
    "signal_type",
    "type",
    "message_type",
    "messageType",
    "body"
  ]

  static func digest(wire: [String: Any]) -> String {
    let canonical = encryptedFields.reduce(into: "") { result, key in
      guard let value = wire[key] else { return }
      let text = String(describing: value)
      result += "\(key.count):\(key)=\(text.count):\(text);"
    }
    return Data(SHA256.hash(data: Data(canonical.utf8))).hexString()
  }
}

enum GalaxySSILinkRetryPolicy {
  static let initialDelaySeconds: TimeInterval = 2
  static let maximumDelaySeconds: TimeInterval = 300

  static func delaySeconds(attempt: Int) -> TimeInterval {
    let exponent = min(max(attempt, 1) - 1, 8)
    return min(initialDelaySeconds * TimeInterval(1 << exponent), maximumDelaySeconds)
  }
}

enum MqttPublishGuard {
  static func attempt<T>(_ operation: () throws -> T) -> Result<T, Error> {
    Result { try operation() }
  }
}

enum MqttOutboxDispatchPolicy {
  static func result(connected: Bool, published: Bool) -> MqttPublishResult {
    connected && published ? .published : .queued
  }
}

final class MqttConnectionRetryPolicy {
  private let delaysMillis: [Int64]
  private var attempt = 0
  private let lock = NSLock()

  init(delaysMillis: [Int64] = [2_000, 5_000, 10_000, 20_000, 30_000]) {
    precondition(!delaysMillis.isEmpty)
    precondition(delaysMillis.allSatisfy { $0 >= 0 })
    self.delaysMillis = delaysMillis
  }

  func nextDelayMillis() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    let delay = delaysMillis[min(attempt, delaysMillis.count - 1)]
    attempt += 1
    return delay
  }

  func reset() {
    lock.lock()
    attempt = 0
    lock.unlock()
  }
}

enum MqttSubscriptionAttemptOutcome: String, Codable, Equatable {
  case stale = "STALE"
  case pending = "PENDING"
  case ready = "READY"
  case retry = "RETRY"
}

final class MqttSubscriptionRecoveryState {
  private var generation = 0
  private var remaining = 0
  private var failed = false
  private let lock = NSLock()

  func begin(subscriptionCount: Int) -> Int {
    precondition(subscriptionCount > 0)
    lock.lock()
    defer { lock.unlock() }
    generation += 1
    remaining = subscriptionCount
    failed = false
    return generation
  }

  func complete(generation attemptGeneration: Int, succeeded: Bool) -> MqttSubscriptionAttemptOutcome {
    lock.lock()
    defer { lock.unlock() }
    guard attemptGeneration == generation, remaining > 0 else {
      return .stale
    }
    if !succeeded {
      failed = true
    }
    remaining -= 1
    if remaining > 0 {
      return .pending
    }
    return failed ? .retry : .ready
  }

  func invalidate() {
    lock.lock()
    generation += 1
    remaining = 0
    failed = false
    lock.unlock()
  }
}

enum GalaxySSIMqttWireChunking {
  static let scheme = "signal-chunk"
  static let defaultDirectLimitBytes = 512 * 1024 - 5
  static let defaultChunkDataBytes = 128 * 1024
  static let maximumReassembledBytes = 2 * 1024 * 1024
  static let maximumChunkCount = 96
  static let maximumPacketBytes = 180 * 1024

  static func isChunk(_ wire: [String: Any]) -> Bool {
    wire.string("scheme") == scheme
  }

  static func encode(
    wirePayload: String,
    directLimitBytes: Int = defaultDirectLimitBytes,
    chunkDataBytes: Int = defaultChunkDataBytes
  ) throws -> [String] {
    precondition(directLimitBytes > 0)
    precondition(chunkDataBytes > 0)
    let bytes = Data(wirePayload.utf8)
    if let rejection = permanentRejectionReason(
      payloadBytes: bytes.count,
      directLimitBytes: directLimitBytes,
      chunkDataBytes: chunkDataBytes
    ) {
      throw GalaxySSIError.invalidPayload(rejection)
    }
    if bytes.count <= directLimitBytes {
      return [wirePayload]
    }
    let count = (bytes.count + chunkDataBytes - 1) / chunkDataBytes
    let digest = sha256(bytes)
    let envelope = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    return try (0..<count).map { index in
      let start = index * chunkDataBytes
      let end = min(start + chunkDataBytes, bytes.count)
      let chunk = bytes.subdata(in: start..<end)
      let packet: [String: Any] = [
        "protocol": GalaxySSILinkProtocol.name,
        "version": GalaxySSILinkProtocol.version,
        "scheme": scheme,
        "transfer_id": digest,
        "chunk_index": index,
        "chunk_count": count,
        "total_bytes": bytes.count,
        "sha256": digest,
        "chunk_sha256": sha256(chunk),
        "from": envelope?.string("from") ?? "",
        "to": envelope?.string("to") ?? "",
        "data": chunk.base64EncodedString()
      ]
      let data = try GalaxySSILinkProtocol.jsonData(packet)
      guard data.count <= maximumPacketBytes else {
        throw GalaxySSIError.invalidPayload("MQTT chunk packet exceeds packet limit.")
      }
      return String(decoding: data, as: UTF8.self)
    }
  }

  static func permanentRejectionReason(
    wirePayload: String,
    directLimitBytes: Int = defaultDirectLimitBytes,
    chunkDataBytes: Int = defaultChunkDataBytes
  ) -> String? {
    precondition(directLimitBytes > 0)
    precondition(chunkDataBytes > 0)
    return permanentRejectionReason(
      payloadBytes: wirePayload.utf8.count,
      directLimitBytes: directLimitBytes,
      chunkDataBytes: chunkDataBytes
    )
  }

  private static func permanentRejectionReason(
    payloadBytes: Int,
    directLimitBytes: Int,
    chunkDataBytes: Int
  ) -> String? {
    if payloadBytes <= directLimitBytes { return nil }
    if payloadBytes > maximumReassembledBytes {
      return "MQTT wire payload exceeds reassembly limit."
    }
    let count = (payloadBytes + chunkDataBytes - 1) / chunkDataBytes
    return (2...maximumChunkCount).contains(count)
      ? nil
      : "MQTT wire payload requires too many chunks."
  }

  static func sha256(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString()
  }
}

final class GalaxySSIMqttChunkAssembler {
  private struct PartialTransfer {
    var chunkCount: Int
    var totalBytes: Int
    var sha256: String
    var from: String
    var to: String
    var chunks: [Int: Data]
    var updatedAt: Date
  }

  private let ttlSeconds: TimeInterval
  private let maximumActiveTransfers: Int
  private let now: () -> Date
  private var transfers: [String: PartialTransfer] = [:]

  init(
    ttlSeconds: TimeInterval = 120,
    maximumActiveTransfers: Int = 16,
    now: @escaping () -> Date = Date.init
  ) {
    self.ttlSeconds = ttlSeconds
    self.maximumActiveTransfers = maximumActiveTransfers
    self.now = now
  }

  func accept(scope: String, wire: [String: Any]) throws -> String? {
    guard GalaxySSIMqttWireChunking.isChunk(wire) else {
      throw GalaxySSIError.invalidPayload("Not a GalaxySSI MQTT chunk.")
    }
    pruneExpired()
    let transferId = wire.string("transfer_id").lowercased()
    let fullHash = wire.string("sha256").lowercased()
    let chunkHash = wire.string("chunk_sha256").lowercased()
    let chunkIndex = wire.int("chunk_index")
    let chunkCount = wire.int("chunk_count")
    let totalBytes = wire.int("total_bytes")
    let from = wire.string("from")
    let to = wire.string("to")
    guard transferId.count == 64, transferId == fullHash else {
      throw GalaxySSIError.invalidPayload("Invalid MQTT transfer identity.")
    }
    guard chunkHash.count == 64 else {
      throw GalaxySSIError.invalidPayload("Invalid MQTT chunk hash.")
    }
    guard (2...GalaxySSIMqttWireChunking.maximumChunkCount).contains(chunkCount) else {
      throw GalaxySSIError.invalidPayload("Invalid MQTT chunk count.")
    }
    guard (0..<chunkCount).contains(chunkIndex) else {
      throw GalaxySSIError.invalidPayload("Invalid MQTT chunk index.")
    }
    guard (1...GalaxySSIMqttWireChunking.maximumReassembledBytes).contains(totalBytes) else {
      throw GalaxySSIError.invalidPayload("Invalid MQTT transfer size.")
    }
    guard let chunk = Data(base64Encoded: wire.string("data")) else {
      throw GalaxySSIError.invalidPayload("Invalid MQTT chunk encoding.")
    }
    guard !chunk.isEmpty, chunk.count <= GalaxySSIMqttWireChunking.defaultChunkDataBytes else {
      throw GalaxySSIError.invalidPayload("Invalid MQTT chunk size.")
    }
    guard GalaxySSIMqttWireChunking.sha256(chunk) == chunkHash else {
      throw GalaxySSIError.invalidPayload("MQTT chunk integrity check failed.")
    }

    let key = "\(scope):\(transferId)"
    if transfers[key] == nil {
      evictOldestIfNeeded()
      transfers[key] = PartialTransfer(
        chunkCount: chunkCount,
        totalBytes: totalBytes,
        sha256: fullHash,
        from: from,
        to: to,
        chunks: [:],
        updatedAt: now()
      )
    }
    guard var partial = transfers[key],
          partial.chunkCount == chunkCount,
          partial.totalBytes == totalBytes,
          partial.sha256 == fullHash,
          partial.from == from,
          partial.to == to else {
      throw GalaxySSIError.invalidPayload("MQTT chunk metadata mismatch.")
    }
    if let previous = partial.chunks[chunkIndex], previous != chunk {
      throw GalaxySSIError.invalidPayload("Conflicting MQTT chunk duplicate.")
    }
    partial.chunks[chunkIndex] = chunk
    partial.updatedAt = now()
    transfers[key] = partial
    guard partial.chunks.count == partial.chunkCount else {
      return nil
    }

    var assembled = Data(capacity: partial.totalBytes)
    for index in 0..<partial.chunkCount {
      guard let chunk = partial.chunks[index] else {
        throw GalaxySSIError.invalidPayload("Missing MQTT chunk.")
      }
      assembled.append(chunk)
    }
    transfers.removeValue(forKey: key)
    guard assembled.count == partial.totalBytes else {
      throw GalaxySSIError.invalidPayload("MQTT transfer length check failed.")
    }
    guard GalaxySSIMqttWireChunking.sha256(assembled) == partial.sha256 else {
      throw GalaxySSIError.invalidPayload("MQTT transfer integrity check failed.")
    }
    return String(data: assembled, encoding: .utf8)
  }

  func clear() {
    transfers.removeAll()
  }

  private func pruneExpired() {
    let cutoff = now().addingTimeInterval(-ttlSeconds)
    transfers = transfers.filter { $0.value.updatedAt >= cutoff }
  }

  private func evictOldestIfNeeded() {
    guard transfers.count >= maximumActiveTransfers,
          let oldest = transfers.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key else {
      return
    }
    transfers.removeValue(forKey: oldest)
  }
}

private extension JSONEncoder {
  static var linkReliability: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

private extension JSONDecoder {
  static var linkReliability: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
