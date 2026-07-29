import CryptoKit
import Foundation

struct PendingLinkMessage: Codable, Equatable, Identifiable {
  var id: String { messageId }
  var messageId: String
  var topic: String
  var wirePayload: String
  var status: String
  var attempts: Int
  var nextAttemptAt: Date
  var createdAt: Date
  var updatedAt: Date
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

@MainActor
final class SignalASILinkDeliveryStore {
  private struct PersistedState: Codable {
    var transportEpoch: String
    var outbox: [PendingLinkMessage]
    var completedInboxIds: [String]
    var pendingIncoming: [String: PendingIncomingLinkMessage]
    var ciphertextBindings: [String: KnownLinkCiphertext]
  }

  private let defaults: UserDefaults
  private let storageKey = "signalasi-ios-link-delivery-v1"
  private let maximumInboxIds = 4096
  private let maximumPendingIncoming = 256
  private let maximumCiphertextBindings = 4096
  private let maximumPendingAge: TimeInterval = 7 * 24 * 60 * 60

  private var state: PersistedState

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
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
    state.outbox.removeAll()
    save()
    return true
  }

  func enqueue(messageId: String, topic: String, wirePayload: String, now: Date = Date()) {
    guard !messageId.isEmpty, !topic.isEmpty, !wirePayload.isEmpty else { return }
    guard !state.outbox.contains(where: { $0.messageId == messageId }) else { return }
    state.outbox.append(
      PendingLinkMessage(
        messageId: messageId,
        topic: topic,
        wirePayload: wirePayload,
        status: "queued",
        attempts: 0,
        nextAttemptAt: now,
        createdAt: now,
        updatedAt: now
      )
    )
    save()
  }

  func markAttempt(messageId: String, now: Date = Date()) {
    updateOutbox(messageId: messageId) { item in
      item.attempts += 1
      item.status = "publishing"
      item.nextAttemptAt = now.addingTimeInterval(SignalASILinkRetryPolicy.delaySeconds(attempt: item.attempts))
      item.updatedAt = now
    }
  }

  func markPublished(messageId: String, now: Date = Date()) {
    updateOutbox(messageId: messageId) { item in
      let attempts = max(item.attempts, 1)
      item.status = "published"
      item.nextAttemptAt = now.addingTimeInterval(SignalASILinkRetryPolicy.delaySeconds(attempt: attempts))
      item.updatedAt = now
    }
  }

  func acknowledge(messageId: String) {
    guard !messageId.isEmpty else { return }
    let before = state.outbox.count
    state.outbox.removeAll { $0.messageId == messageId }
    if state.outbox.count != before {
      save()
    }
  }

  func pending(now: Date = Date()) -> [PendingLinkMessage] {
    state.outbox
      .filter { $0.nextAttemptAt <= now }
      .sorted { left, right in
        if left.nextAttemptAt == right.nextAttemptAt {
          return left.createdAt < right.createdAt
        }
        return left.nextAttemptAt < right.nextAttemptAt
      }
  }

  func nextRetryDelay(now: Date = Date()) -> TimeInterval? {
    state.outbox
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

  func discardRoutes(_ routes: SignalASILinkRoutes) -> Int {
    let topics: Set<String> = [
      routes.pairingTopic,
      routes.upTopic,
      routes.downTopic,
      routes.controlTopic
    ]
    let before = state.outbox.count
    state.outbox.removeAll { topics.contains($0.topic) }
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
      throw SignalASIError.invalidPayload("ciphertext is already bound to another message.")
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
    state = PersistedState(
      transportEpoch: "",
      outbox: [],
      completedInboxIds: [],
      pendingIncoming: [:],
      ciphertextBindings: [:]
    )
    save()
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

enum SignalASILinkDeliveryAckPolicy {
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

enum SignalASILinkCiphertextReplayPolicy {
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

enum SignalASILinkRetryPolicy {
  static let initialDelaySeconds: TimeInterval = 2
  static let maximumDelaySeconds: TimeInterval = 300

  static func delaySeconds(attempt: Int) -> TimeInterval {
    let exponent = min(max(attempt, 1) - 1, 8)
    return min(initialDelaySeconds * TimeInterval(1 << exponent), maximumDelaySeconds)
  }
}

enum SignalASIMqttWireChunking {
  static let scheme = "signal-chunk"
  static let defaultDirectLimitBytes = 48 * 1024
  static let defaultChunkDataBytes = 32 * 1024
  static let maximumReassembledBytes = 2 * 1024 * 1024
  static let maximumChunkCount = 64
  static let maximumPacketBytes = 60 * 1024

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
    if bytes.count <= directLimitBytes {
      return [wirePayload]
    }
    guard bytes.count <= maximumReassembledBytes else {
      throw SignalASIError.invalidPayload("MQTT wire payload exceeds reassembly limit.")
    }
    let count = (bytes.count + chunkDataBytes - 1) / chunkDataBytes
    guard (2...maximumChunkCount).contains(count) else {
      throw SignalASIError.invalidPayload("MQTT wire payload requires too many chunks.")
    }
    let digest = sha256(bytes)
    let envelope = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    return try (0..<count).map { index in
      let start = index * chunkDataBytes
      let end = min(start + chunkDataBytes, bytes.count)
      let chunk = bytes.subdata(in: start..<end)
      let packet: [String: Any] = [
        "protocol": SignalASILinkProtocol.name,
        "version": SignalASILinkProtocol.version,
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
      let data = try SignalASILinkProtocol.jsonData(packet)
      guard data.count <= maximumPacketBytes else {
        throw SignalASIError.invalidPayload("MQTT chunk packet exceeds packet limit.")
      }
      return String(decoding: data, as: UTF8.self)
    }
  }

  static func sha256(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString()
  }
}

final class SignalASIMqttChunkAssembler {
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
    guard SignalASIMqttWireChunking.isChunk(wire) else {
      throw SignalASIError.invalidPayload("Not a SignalASI MQTT chunk.")
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
      throw SignalASIError.invalidPayload("Invalid MQTT transfer identity.")
    }
    guard chunkHash.count == 64 else {
      throw SignalASIError.invalidPayload("Invalid MQTT chunk hash.")
    }
    guard (2...SignalASIMqttWireChunking.maximumChunkCount).contains(chunkCount) else {
      throw SignalASIError.invalidPayload("Invalid MQTT chunk count.")
    }
    guard (0..<chunkCount).contains(chunkIndex) else {
      throw SignalASIError.invalidPayload("Invalid MQTT chunk index.")
    }
    guard (1...SignalASIMqttWireChunking.maximumReassembledBytes).contains(totalBytes) else {
      throw SignalASIError.invalidPayload("Invalid MQTT transfer size.")
    }
    guard let chunk = Data(base64Encoded: wire.string("data")) else {
      throw SignalASIError.invalidPayload("Invalid MQTT chunk encoding.")
    }
    guard !chunk.isEmpty, chunk.count <= SignalASIMqttWireChunking.defaultChunkDataBytes else {
      throw SignalASIError.invalidPayload("Invalid MQTT chunk size.")
    }
    guard SignalASIMqttWireChunking.sha256(chunk) == chunkHash else {
      throw SignalASIError.invalidPayload("MQTT chunk integrity check failed.")
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
      throw SignalASIError.invalidPayload("MQTT chunk metadata mismatch.")
    }
    if let previous = partial.chunks[chunkIndex], previous != chunk {
      throw SignalASIError.invalidPayload("Conflicting MQTT chunk duplicate.")
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
        throw SignalASIError.invalidPayload("Missing MQTT chunk.")
      }
      assembled.append(chunk)
    }
    transfers.removeValue(forKey: key)
    guard assembled.count == partial.totalBytes else {
      throw SignalASIError.invalidPayload("MQTT transfer length check failed.")
    }
    guard SignalASIMqttWireChunking.sha256(assembled) == partial.sha256 else {
      throw SignalASIError.invalidPayload("MQTT transfer integrity check failed.")
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
