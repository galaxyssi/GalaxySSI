import CryptoKit
import Foundation

struct AgentResultRecoveryIdentity: Codable, Equatable, Hashable {
  var clientRouteId: String
  var conversationId: String
  var taskId: String
  var turnId: String
  var contactId: String
  var sourceMessageId: String
  var agentId: String

  var isValid: Bool {
    [clientRouteId, conversationId, taskId, turnId, contactId, sourceMessageId, agentId]
      .allSatisfy { !$0.isBlank && $0.count <= 200 }
  }
}

struct AgentResultRecoveryPage: Equatable {
  var identity: AgentResultRecoveryIdentity
  var pageIndex: Int
  var pageCount: Int
  var totalBytes: Int
  var sha256: String
  var pageSHA256: String
  var dataBase64: String
  var status: String = "ready"
}

final class AgentResultRecoveryAssembler {
  static let pageBytes = 16 * 1_024
  static let maximumResultBytes = 128 * 1_024

  private let identity: AgentResultRecoveryIdentity
  private let stillPending: () -> Bool
  private var data = Data()
  private var expectedDigest = ""
  private var expectedTotal = 0
  private var expectedPages = 0
  private var nextPage = 0

  init(identity: AgentResultRecoveryIdentity, stillPending: @escaping () -> Bool = { true }) {
    self.identity = identity
    self.stillPending = stillPending
  }

  func consume(_ page: AgentResultRecoveryPage) -> AgentConnectorResponse? {
    guard identity.isValid, stillPending(), page.identity == identity,
          page.status == "ready", page.pageIndex == nextPage,
          Self.validDigest(page.sha256), Self.validDigest(page.pageSHA256),
          page.totalBytes > 0, page.totalBytes <= Self.maximumResultBytes,
          page.pageCount == (page.totalBytes + Self.pageBytes - 1) / Self.pageBytes,
          page.pageCount > 0, page.pageIndex < page.pageCount else {
      reset()
      return nil
    }
    if nextPage == 0 {
      expectedDigest = page.sha256
      expectedTotal = page.totalBytes
      expectedPages = page.pageCount
      data.reserveCapacity(expectedTotal)
    } else if page.sha256 != expectedDigest || page.totalBytes != expectedTotal ||
                page.pageCount != expectedPages {
      reset()
      return nil
    }
    guard page.dataBase64.count <= ((Self.pageBytes + 2) / 3) * 4,
          let chunk = Data(base64Encoded: page.dataBase64),
          chunk.count == min(Self.pageBytes, expectedTotal - nextPage * Self.pageBytes),
          Self.sha256(chunk) == page.pageSHA256 else {
      reset()
      return nil
    }
    data.append(chunk)
    nextPage += 1
    guard nextPage == expectedPages else { return nil }
    defer { reset() }
    guard stillPending(), data.count == expectedTotal, Self.sha256(data) == expectedDigest,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          Self.identity(from: object) == identity,
          object["type"] as? String == "text",
          object["task_status"] as? String == "completed" else {
      return nil
    }
    let exact = Self.exactContent(object)
    let content = exact.ifBlank(object["content"] as? String ?? "")
    let richOutput = Self.richOutput(object["rich_output"])
    guard !content.isBlank || !richOutput.isBlank,
          let sourceMessageId = Int64(identity.sourceMessageId) else { return nil }
    return AgentConnectorResponse(
      sourceMessageId: sourceMessageId,
      contactId: identity.contactId,
      content: content,
      conversationId: identity.conversationId,
      turnId: identity.turnId,
      taskId: identity.taskId,
      richOutputJson: richOutput
    )
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func identity(from object: [String: Any]) -> AgentResultRecoveryIdentity {
    let sourceMessageId = (object["source_message_id"] as? String)
      ?? (object["source_message_id"] as? NSNumber)?.stringValue
      ?? ""
    return AgentResultRecoveryIdentity(
      clientRouteId: object["client_route_id"] as? String ?? "",
      conversationId: object["conversation_id"] as? String ?? "",
      taskId: object["task_id"] as? String ?? "",
      turnId: object["turn_id"] as? String ?? "",
      contactId: object["contact_id"] as? String ?? "",
      sourceMessageId: sourceMessageId,
      agentId: object["agent_id"] as? String ?? ""
    )
  }

  private static func exactContent(_ object: [String: Any]) -> String {
    guard object["exact_content_encoding"] as? String == "base64-utf8",
          let encoded = object["exact_content_b64"] as? String,
          encoded.count <= 256 * 1_024,
          let data = Data(base64Encoded: encoded), data.count <= maximumResultBytes else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  private static func richOutput(_ value: Any?) -> String {
    guard let value, JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          data.count <= maximumResultBytes else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  private static func validDigest(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }

  private func reset() {
    data.resetBytes(in: 0..<data.count)
    data.removeAll(keepingCapacity: false)
    expectedDigest = ""
    expectedTotal = 0
    expectedPages = 0
    nextPage = 0
  }
}

struct AgentConnectorResponse: Codable, Equatable {
  var sourceMessageId: Int64
  var contactId: String
  var resolvedContactId: String
  var content: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var success: Bool
  var inputTokens: Int64
  var outputTokens: Int64
  var costMicros: Int64
  var richOutputJson: String
  var receivedAtMillis: Int64

  init(
    sourceMessageId: Int64,
    contactId: String = "",
    resolvedContactId: String = "",
    content: String = "",
    conversationId: String = "",
    turnId: String = "",
    taskId: String = "",
    success: Bool = true,
    inputTokens: Int64 = 0,
    outputTokens: Int64 = 0,
    costMicros: Int64 = 0,
    richOutputJson: String = "",
    receivedAtMillis: Int64 = 0
  ) {
    self.sourceMessageId = max(sourceMessageId, 0)
    self.contactId = contactId
    self.resolvedContactId = resolvedContactId
    self.content = String(content.prefix(Self.maxContentCharacters))
    self.conversationId = conversationId
    self.turnId = turnId
    self.taskId = taskId
    self.success = success
    self.inputTokens = max(inputTokens, 0)
    self.outputTokens = max(outputTokens, 0)
    self.costMicros = max(costMicros, 0)
    self.richOutputJson = String(richOutputJson.prefix(Self.maxRichOutputCharacters))
    self.receivedAtMillis = max(receivedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case sourceMessageId = "source_message_id"
    case contactId = "contact_id"
    case resolvedContactId = "resolved_contact_id"
    case content
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case taskId = "task_id"
    case success
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case costMicros = "cost_micros"
    case richOutputJson = "rich_output"
    case receivedAtMillis = "received_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      sourceMessageId: try container.decodeIfPresent(Int64.self, forKey: .sourceMessageId) ?? 0,
      contactId: try container.decodeIfPresent(String.self, forKey: .contactId) ?? "",
      resolvedContactId: try container.decodeIfPresent(String.self, forKey: .resolvedContactId) ?? "",
      content: try container.decodeIfPresent(String.self, forKey: .content) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      turnId: try container.decodeIfPresent(String.self, forKey: .turnId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      success: try container.decodeIfPresent(Bool.self, forKey: .success) ?? true,
      inputTokens: try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0,
      outputTokens: try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0,
      costMicros: try container.decodeIfPresent(Int64.self, forKey: .costMicros) ?? 0,
      richOutputJson: try container.decodeIfPresent(String.self, forKey: .richOutputJson) ?? "",
      receivedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .receivedAtMillis) ?? 0
    )
  }

  static let maxContentCharacters = 24_000
  static let maxRichOutputCharacters = 48_000

  static func fromPayload(
    _ payload: [String: Any],
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> AgentConnectorResponse? {
    let sourceMessageId = Int64(payload.string("source_message_id")) ?? Int64(payload.int("source_message_id"))
    guard sourceMessageId > 0 else { return nil }
    let content = payload.string("content")
      .ifBlank(payload.string("text"))
      .ifBlank(payload.string("error"))
    let richOutput = payload.string("rich_output")
      .ifBlank(payload.string("rich_output_json"))
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !richOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    let receivedAtMillis = Int64(
      payload.string("received_at_millis")
        .ifBlank(payload.string("received_at"))
        .ifBlank(payload.string("time"))
    ) ?? Int64(payload.int("received_at_millis"))
    return AgentConnectorResponse(
      sourceMessageId: sourceMessageId,
      contactId: payload.string("contact_id"),
      resolvedContactId: payload.string("resolved_contact_id"),
      content: content,
      conversationId: payload.string("conversation_id"),
      turnId: payload.string("turn_id"),
      taskId: payload.string("task_id"),
      success: payloadBool(payload["success"], defaultValue: true),
      inputTokens: Int64(payload.string("input_tokens")) ?? Int64(payload.int("input_tokens")),
      outputTokens: Int64(payload.string("output_tokens")) ?? Int64(payload.int("output_tokens")),
      costMicros: Int64(payload.string("cost_micros")) ?? Int64(payload.int("cost_micros")),
      richOutputJson: richOutput,
      receivedAtMillis: receivedAtMillis > 0 ? receivedAtMillis : max(nowMillis, 0)
    )
  }

  private static func payloadBool(_ value: Any?, defaultValue: Bool) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String {
      switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "true", "1", "yes": return true
      case "false", "0", "no": return false
      default: break
      }
    }
    return defaultValue
  }
}

protocol AgentConnectorResponseSink: AnyObject {
  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool
  func pending() -> [AgentConnectorResponse]
  func remove(_ response: AgentConnectorResponse)
  func clear()
}

extension AgentConnectorResponseSink {
  func pending(limit: Int) -> [AgentConnectorResponse] {
    Array(pending().prefix(max(1, min(limit, 64))))
  }
}

final class InMemoryAgentConnectorResponseStore: AgentConnectorResponseSink {
  private let lock = NSRecursiveLock()
  private var responses: [AgentConnectorResponse] = []

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    responses.append(response)
    return true
  }

  func pending() -> [AgentConnectorResponse] {
    lock.lock()
    defer { lock.unlock() }
    return responses
  }

  func remove(_ response: AgentConnectorResponse) {
    lock.lock()
    defer { lock.unlock() }
    responses.removeAll {
      $0.sourceMessageId == response.sourceMessageId && $0.contactId == response.contactId
    }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    responses.removeAll()
  }
}

protocol AgentConnectorResponseListener: AnyObject {
  func onConnectorResponse(_ response: AgentConnectorResponse)
}

final class AgentManagedConnectorResponseRegistry {
  static let shared = AgentManagedConnectorResponseRegistry()

  private struct Interceptor {
    var ownerId: String
    var conversationId: String
    var turnId: String
    var taskId: String
    var consume: (AgentConnectorResponse) -> Bool
  }

  private let lock = NSRecursiveLock()
  private var interceptors: [String: Interceptor] = [:]

  func register(
    sourceMessageId: Int64,
    contactId: String = "",
    ownerId: String,
    conversationId: String = "",
    turnId: String = "",
    taskId: String = "",
    consume: @escaping (AgentConnectorResponse) -> Bool
  ) throws {
    guard sourceMessageId > 0 else {
      throw AgentRuntimeCapabilityError.invalid("Managed response source id must be positive")
    }
    let cleanOwner = ownerId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanOwner.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("Managed response owner id must not be blank")
    }
    lock.lock()
    defer { lock.unlock() }
    interceptors[key(sourceMessageId: sourceMessageId, contactId: contactId)] = Interceptor(
      ownerId: cleanOwner,
      conversationId: conversationId.trimmingCharacters(in: .whitespacesAndNewlines),
      turnId: turnId.trimmingCharacters(in: .whitespacesAndNewlines),
      taskId: taskId.trimmingCharacters(in: .whitespacesAndNewlines),
      consume: consume
    )
  }

  func consume(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    guard let entry = matchingEntry(response) else {
      lock.unlock()
      return false
    }
    guard interceptors.removeValue(forKey: entry.0) != nil else {
      lock.unlock()
      return false
    }
    lock.unlock()
    return entry.1.consume(response)
  }

  func contains(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return matchingEntry(response) != nil
  }

  func unregisterOwner(_ ownerId: String) {
    let cleanOwner = ownerId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanOwner.isEmpty else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    interceptors = interceptors.filter { $0.value.ownerId != cleanOwner }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    interceptors.removeAll()
  }

  private func key(sourceMessageId: Int64, contactId: String) -> String {
    "\(sourceMessageId):\(contactId.trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  private func matchingEntry(_ response: AgentConnectorResponse) -> (String, Interceptor)? {
    guard response.sourceMessageId > 0 else { return nil }
    let exactKey = key(sourceMessageId: response.sourceMessageId, contactId: response.contactId)
    let wildcardKey = key(sourceMessageId: response.sourceMessageId, contactId: "")
    if let exact = interceptors[exactKey], identityMatches(exact, response) {
      return (exactKey, exact)
    }
    if let wildcard = interceptors[wildcardKey], identityMatches(wildcard, response) {
      return (wildcardKey, wildcard)
    }
    let prefix = "\(response.sourceMessageId):"
    let aliases = interceptors.compactMap { item -> (String, Interceptor)? in
      guard item.key.hasPrefix(prefix), identityMatches(item.value, response) else { return nil }
      return (item.key, item.value)
    }.prefix(2)
    return aliases.count == 1 ? aliases.first : nil
  }

  private func identityMatches(_ interceptor: Interceptor, _ response: AgentConnectorResponse) -> Bool {
    AgentTaskIdentityPolicy.matchesResponseIdentity(
      expectedConversationId: interceptor.conversationId,
      expectedTurnId: interceptor.turnId,
      expectedTaskId: interceptor.taskId,
      actualConversationId: response.conversationId,
      actualTurnId: response.turnId,
      actualTaskId: response.taskId
    )
  }
}

final class AgentConnectorResponseStore: AgentConnectorResponseSink {
  private let lock = NSRecursiveLock()
  private let nowMillis: () -> Int64
  private var responses: [AgentConnectorResponse]

  init(
    serialized: String = "[]",
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.nowMillis = nowMillis
    self.responses = AgentConnectorResponseStoreCodec.decode(serialized, nowMillis: nowMillis())
  }

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    append(response)
  }

  @discardableResult
  func append(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let now = max(nowMillis(), 0)
    guard let normalized = AgentConnectorResponseNormalizer.normalized(response, nowMillis: now) else {
      responses = pendingLocked(nowMillis: now)
      return false
    }
    responses = (pendingLocked(nowMillis: now).filter {
      !Self.matches($0, normalized)
    } + [normalized])
      .sorted { $0.receivedAtMillis < $1.receivedAtMillis }
    return true
  }

  func pending() -> [AgentConnectorResponse] {
    pending(nowMillis: nowMillis())
  }

  func pending(nowMillis: Int64) -> [AgentConnectorResponse] {
    lock.lock()
    defer { lock.unlock() }
    responses = pendingLocked(nowMillis: max(nowMillis, 0))
    return responses
  }

  func remove(_ response: AgentConnectorResponse) {
    lock.lock()
    defer { lock.unlock() }
    responses = pendingLocked(nowMillis: nowMillis()).filter {
      !Self.matches($0, response)
    }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    responses.removeAll()
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    responses = pendingLocked(nowMillis: nowMillis())
    return AgentConnectorResponseStoreCodec.encode(responses)
  }

  private func pendingLocked(nowMillis: Int64) -> [AgentConnectorResponse] {
    responses.compactMap {
      AgentConnectorResponseNormalizer.normalized($0, nowMillis: nowMillis)
    }
  }

  private static func matches(
    _ candidate: AgentConnectorResponse,
    _ expected: AgentConnectorResponse
  ) -> Bool {
    candidate.sourceMessageId == expected.sourceMessageId
      && candidate.contactId == expected.contactId
      && candidate.conversationId == expected.conversationId
      && candidate.turnId == expected.turnId
      && candidate.taskId == expected.taskId
  }
}

final class AgentConnectorResponseBus {
  private let lock = NSRecursiveLock()
  private var listeners: [UUID: (AgentConnectorResponse) -> Void] = [:]
  private let registry: AgentManagedConnectorResponseRegistry
  private let managedLedger: AgentManagedResponseLedger?
  private let store: AgentConnectorResponseSink
  private let terminalStore: AgentTerminalDeliveryStoring
  private let globalRunSlots: AgentGlobalRunSlotStoring
  private let nowMillis: () -> Int64

  init(
    registry: AgentManagedConnectorResponseRegistry = .shared,
    managedLedger: AgentManagedResponseLedger? = UserDefaultsAgentManagedResponseLedger(),
    store: AgentConnectorResponseSink = UserDefaultsAgentConnectorResponseStore(),
    terminalStore: AgentTerminalDeliveryStoring = UserDefaultsAgentTerminalDeliveryStore(),
    globalRunSlots: AgentGlobalRunSlotStoring = InMemoryAgentGlobalRunSlotStore(),
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.registry = registry
    self.managedLedger = managedLedger
    self.store = store
    self.terminalStore = terminalStore
    self.globalRunSlots = globalRunSlots
    self.nowMillis = nowMillis
  }

  @discardableResult
  func addListener(_ listener: @escaping (AgentConnectorResponse) -> Void) -> UUID {
    lock.lock()
    defer { lock.unlock() }
    let token = UUID()
    listeners[token] = listener
    return token
  }

  func removeListener(_ token: UUID) {
    lock.lock()
    defer { lock.unlock() }
    listeners.removeValue(forKey: token)
  }

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    guard let normalized = AgentConnectorResponseNormalizer.normalized(response, nowMillis: nowMillis()) else {
      return false
    }
    globalRunSlots.release(sourceMessageId: String(normalized.sourceMessageId))
    if terminalStore.isTerminal(normalized) {
      store.remove(normalized)
      return true
    }
    if registry.consume(normalized) {
      return true
    }
    if managedLedger?.complete(normalized) != nil {
      return true
    }
    store.publish(normalized)
    let callbacks: [(AgentConnectorResponse) -> Void]
    lock.lock()
    callbacks = Array(listeners.values)
    lock.unlock()
    callbacks.forEach { $0(normalized) }
    return false
  }

  func pending() -> [AgentConnectorResponse] {
    store.pending()
  }

  func pending(limit: Int) -> [AgentConnectorResponse] {
    store.pending(limit: limit)
  }

  func remove(_ response: AgentConnectorResponse) {
    store.remove(response)
  }

  func isTerminal(_ response: AgentConnectorResponse) -> Bool {
    terminalStore.isTerminal(response)
  }

  func markTerminal(_ delivery: AgentTerminalDelivery) {
    terminalStore.mark(delivery)
  }

  func clear() {
    store.clear()
    registry.clear()
    managedLedger?.clear()
    lock.lock()
    defer { lock.unlock() }
    listeners.removeAll()
  }
}

enum AgentConnectorResponseStoreCodec {
  static func encode(_ responses: [AgentConnectorResponse]) -> String {
    AgentMcpJSONCodec.stringify(.array(responses.map(responseObject)))
  }

  static func decode(
    _ raw: String,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [AgentConnectorResponse] {
    guard let data = raw.data(using: .utf8),
          let values = try? JSONDecoder().decode([AgentMcpJSONValue].self, from: data) else {
      return []
    }
    return values.compactMap { value in
      guard case .object(let object) = value else {
        return nil
      }
      let receivedAt = object.int64("received_at") > 0
        ? object.int64("received_at")
        : object.int64("received_at_millis")
      let response = AgentConnectorResponse(
        sourceMessageId: object.int64("source_message_id"),
        contactId: object.string("contact_id"),
        resolvedContactId: object.string("resolved_contact_id"),
        content: object.string("content"),
        conversationId: object.string("conversation_id"),
        turnId: object.string("turn_id"),
        taskId: object.string("task_id"),
        success: object["success"] == nil ? true : object.bool("success"),
        inputTokens: object.int64("input_tokens"),
        outputTokens: object.int64("output_tokens"),
        costMicros: object.int64("cost_micros"),
        richOutputJson: object.string("rich_output"),
        receivedAtMillis: receivedAt
      )
      return AgentConnectorResponseNormalizer.normalized(response, nowMillis: nowMillis)
    }
  }

  private static func responseObject(_ response: AgentConnectorResponse) -> AgentMcpJSONValue {
    .object([
      "source_message_id": .int(response.sourceMessageId),
      "contact_id": .string(response.contactId),
      "resolved_contact_id": .string(response.resolvedContactId),
      "content": .string(String(response.content.prefix(AgentConnectorResponse.maxContentCharacters))),
      "conversation_id": .string(response.conversationId),
      "turn_id": .string(response.turnId),
      "task_id": .string(response.taskId),
      "success": .bool(response.success),
      "input_tokens": .int(response.inputTokens),
      "output_tokens": .int(response.outputTokens),
      "cost_micros": .int(response.costMicros),
      "rich_output": .string(AgentConnectorRichOutput.normalize(response.richOutputJson)),
      "received_at": .int(response.receivedAtMillis)
    ])
  }
}

enum AgentConnectorResponseNormalizer {
  static func normalized(
    _ response: AgentConnectorResponse,
    nowMillis: Int64
  ) -> AgentConnectorResponse? {
    guard response.sourceMessageId > 0 else {
      return nil
    }
    let richOutput = AgentConnectorRichOutput.normalize(response.richOutputJson)
    let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? AgentConnectorRichOutput.fallbackText(richOutput)
      : response.content
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !richOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return AgentConnectorResponse(
      sourceMessageId: response.sourceMessageId,
      contactId: response.contactId,
      resolvedContactId: response.resolvedContactId,
      content: String(content.prefix(AgentConnectorResponse.maxContentCharacters)),
      conversationId: response.conversationId,
      turnId: response.turnId,
      taskId: response.taskId,
      success: response.success,
      inputTokens: response.inputTokens,
      outputTokens: response.outputTokens,
      costMicros: response.costMicros,
      richOutputJson: richOutput,
      receivedAtMillis: response.receivedAtMillis > 0 ? response.receivedAtMillis : max(nowMillis, 0)
    )
  }
}

enum AgentConnectorRichOutput {
  static func normalize(_ raw: String) -> String {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty,
          clean.count <= maxSerializedCharacters,
          let data = clean.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          (object["version"] as? Int ?? 1) <= 1,
          renderableBlocks(in: object).isEmpty == false else {
      return ""
    }
    return clean
  }

  static func fallbackText(_ raw: String) -> String {
    guard let data = raw.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return ""
    }
    for block in renderableBlocks(in: object) {
      for key in ["text", "title", "fallback_text", "uri"] {
        if let value = block[key] as? String {
          let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if !clean.isEmpty {
            return String(clean.prefix(AgentConnectorResponse.maxContentCharacters))
          }
        }
      }
    }
    return ""
  }

  private static func renderableBlocks(in object: [String: Any]) -> [[String: Any]] {
    guard let blocks = object["blocks"] as? [[String: Any]] else {
      return []
    }
    return blocks.prefix(maxBlocks).filter { block in
      ["text", "title", "fallback_text", "uri", "data_b64"].contains { key in
        guard let value = block[key] as? String else {
          return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
    }
  }

  private static let maxBlocks = 100
  private static let maxSerializedCharacters = 640 * 1_024
}
