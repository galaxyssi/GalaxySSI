import Foundation

struct AgentConnectorResponse: Codable, Equatable {
  var sourceMessageId: Int64
  var contactId: String
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
    let exactKey = key(sourceMessageId: response.sourceMessageId, contactId: response.contactId)
    let wildcardKey = key(sourceMessageId: response.sourceMessageId, contactId: "")
    let entry = interceptors[exactKey].map { (exactKey, $0) } ??
      interceptors[wildcardKey].map { (wildcardKey, $0) }
    guard let entry,
          AgentTaskIdentityPolicy.matchesResponseIdentity(
            expectedConversationId: entry.1.conversationId,
            expectedTurnId: entry.1.turnId,
            expectedTaskId: entry.1.taskId,
            actualConversationId: response.conversationId,
            actualTurnId: response.turnId,
            actualTaskId: response.taskId
          ) else {
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
}

final class AgentConnectorResponseStore: AgentConnectorResponseSink {
  static let maxResponses = 30
  static let maxResponseAgeMillis: Int64 = 24 * 60 * 60 * 1_000

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
      !($0.sourceMessageId == normalized.sourceMessageId && $0.contactId == normalized.contactId)
    } + [normalized])
      .sorted { $0.receivedAtMillis < $1.receivedAtMillis }
      .suffix(Self.maxResponses)
      .map { $0 }
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
      !($0.sourceMessageId == response.sourceMessageId && $0.contactId == response.contactId)
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
    let cutoff = nowMillis - Self.maxResponseAgeMillis
    return responses.compactMap { response in
      guard response.receivedAtMillis >= cutoff else {
        return nil
      }
      return AgentConnectorResponseNormalizer.normalized(response, nowMillis: nowMillis)
    }
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
    let cutoff = max(nowMillis, 0) - AgentConnectorResponseStore.maxResponseAgeMillis
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
      guard receivedAt >= cutoff else {
        return nil
      }
      return AgentConnectorResponseNormalizer.normalized(response, nowMillis: nowMillis)
    }
  }

  private static func responseObject(_ response: AgentConnectorResponse) -> AgentMcpJSONValue {
    .object([
      "source_message_id": .int(response.sourceMessageId),
      "contact_id": .string(response.contactId),
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
