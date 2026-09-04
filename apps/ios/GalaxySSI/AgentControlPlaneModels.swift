import CryptoKit
import Foundation

struct AgentProtocolAgreement: Codable, Equatable {
  var version: String
  var features: Set<String>

  init(version: String, features: Set<String> = []) {
    self.version = version.trimmingCharacters(in: .whitespacesAndNewlines)
    self.features = features
  }
}

enum AgentProtocolNegotiator {
  static func negotiate(local: AgentProtocolRange, remote: AgentProtocolRange) -> AgentProtocolAgreement? {
    guard let localMinimum = protocolVersion(local.minimum),
      let localMaximum = protocolVersion(local.maximum),
      let remoteMinimum = protocolVersion(remote.minimum),
      let remoteMaximum = protocolVersion(remote.maximum) else {
      return nil
    }
    let minimum = max(localMinimum, remoteMinimum)
    let maximum = min(localMaximum, remoteMaximum)
    guard minimum <= maximum else {
      return nil
    }
    let preferred = [protocolVersion(local.preferred), protocolVersion(remote.preferred)]
      .compactMap { $0 }
      .filter { $0 >= minimum && $0 <= maximum }
      .max() ?? maximum
    return AgentProtocolAgreement(
      version: preferred.wireValue,
      features: local.features.intersection(remote.features)
    )
  }

  private static func protocolVersion(_ value: String) -> AgentControlProtocolVersion? {
    var clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.hasPrefix("v") {
      clean.removeFirst()
    }
    let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
    guard let major = parts.first.flatMap({ Int($0) }) else {
      return nil
    }
    let minor = parts.dropFirst().first.flatMap { Int($0) } ?? 0
    return AgentControlProtocolVersion(major: major, minor: minor)
  }
}

private struct AgentControlProtocolVersion: Comparable {
  var major: Int
  var minor: Int

  var wireValue: String { "\(major).\(minor)" }

  static func < (lhs: AgentControlProtocolVersion, rhs: AgentControlProtocolVersion) -> Bool {
    lhs.major == rhs.major ? lhs.minor < rhs.minor : lhs.major < rhs.major
  }
}

struct AgentArtifactReference: Codable, Equatable, Identifiable {
  var id: String
  var uri: String
  var name: String
  var mimeType: String
  var metadataJson: String
  var createdAtMillis: Int64

  init(
    id: String,
    uri: String,
    name: String = "",
    mimeType: String = "",
    metadataJson: String = "",
    createdAtMillis: Int64 = 0
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.uri = uri.trimmingCharacters(in: .whitespacesAndNewlines)
    self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextCharacters))
    self.mimeType = String(mimeType.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTextCharacters))
    self.metadataJson = String(metadataJson.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxMetadataCharacters))
    self.createdAtMillis = max(createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case uri
    case name
    case mimeType = "mime_type"
    case metadataJson = "metadata_json"
    case createdAtMillis = "created_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      uri: try container.decodeIfPresent(String.self, forKey: .uri) ?? "",
      name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
      mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "",
      metadataJson: try container.decodeIfPresent(String.self, forKey: .metadataJson) ?? "",
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0
    )
  }

  private static let maxTextCharacters = 512
  private static let maxMetadataCharacters = 32_000
}

struct AgentControlMessage: Codable, Equatable, Identifiable {
  var messageId: String
  var role: String
  var text: String
  var attachments: [AgentArtifactReference]
  var deliveryMode: AgentDeliveryMode

  var id: String { messageId }

  init(
    messageId: String,
    role: String,
    text: String,
    attachments: [AgentArtifactReference] = [],
    deliveryMode: AgentDeliveryMode = .respond
  ) {
    self.messageId = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.role = String(role.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxRoleCharacters))
    self.text = String(text.prefix(Self.maxTextCharacters))
    self.attachments = Array(attachments.prefix(Self.maxAttachments))
    self.deliveryMode = deliveryMode
  }

  enum CodingKeys: String, CodingKey {
    case messageId = "message_id"
    case role
    case text
    case attachments
    case deliveryMode = "delivery_mode"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      messageId: try container.decodeIfPresent(String.self, forKey: .messageId) ?? UUID().uuidString,
      role: try container.decodeIfPresent(String.self, forKey: .role) ?? "",
      text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
      attachments: try container.decodeIfPresent([AgentArtifactReference].self, forKey: .attachments) ?? [],
      deliveryMode: try container.decodeIfPresent(AgentDeliveryMode.self, forKey: .deliveryMode) ?? .respond
    )
  }

  private static let maxRoleCharacters = 80
  private static let maxTextCharacters = 64_000
  private static let maxAttachments = 64
}

struct AgentRecoverableRun: Codable, Equatable {
  var handle: AgentRunHandle
  var lastEventSequence: Int64
  var checkpoint: AgentMcpJSONObject

  init(
    handle: AgentRunHandle,
    lastEventSequence: Int64,
    checkpoint: AgentMcpJSONObject = [:]
  ) {
    self.handle = handle
    self.lastEventSequence = max(lastEventSequence, 0)
    self.checkpoint = checkpoint
  }

  enum CodingKeys: String, CodingKey {
    case handle
    case lastEventSequence = "last_event_sequence"
    case checkpoint
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      handle: try container.decode(AgentRunHandle.self, forKey: .handle),
      lastEventSequence: try container.decodeIfPresent(Int64.self, forKey: .lastEventSequence) ?? 0,
      checkpoint: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .checkpoint) ?? [:]
    )
  }
}

struct AgentHandoffRequest: Codable, Equatable, Identifiable {
  var handoffId: String
  var conversationId: String
  var taskId: String
  var runId: String
  var parentRunId: String
  var fromAgentId: String
  var toAgentId: String
  var returnToAgentId: String
  var reason: String
  var deliveryMode: AgentDeliveryMode
  var requiredCapabilities: Set<AgentCapability>
  var artifactIds: [String]
  var checkpoint: AgentMcpJSONObject
  var context: AgentMcpJSONObject
  var createdAtMillis: Int64

  var id: String { handoffId }

  init(
    handoffId: String = UUID().uuidString,
    conversationId: String,
    taskId: String,
    runId: String,
    parentRunId: String? = nil,
    fromAgentId: String,
    toAgentId: String,
    returnToAgentId: String? = nil,
    reason: String,
    deliveryMode: AgentDeliveryMode = .respond,
    requiredCapabilities: Set<AgentCapability> = [],
    artifactIds: [String] = [],
    checkpoint: AgentMcpJSONObject = [:],
    context: AgentMcpJSONObject = [:],
    createdAtMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) {
    let cleanRunId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanFromAgentId = fromAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.handoffId = handoffId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.conversationId = String(conversationId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxIdCharacters))
    self.taskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.runId = cleanRunId
    self.parentRunId = (parentRunId ?? cleanRunId).trimmingCharacters(in: .whitespacesAndNewlines)
    if self.parentRunId.isEmpty {
      self.parentRunId = cleanRunId
    }
    self.fromAgentId = cleanFromAgentId
    self.toAgentId = toAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.returnToAgentId = (returnToAgentId ?? cleanFromAgentId).trimmingCharacters(in: .whitespacesAndNewlines)
    if self.returnToAgentId.isEmpty {
      self.returnToAgentId = cleanFromAgentId
    }
    self.reason = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxReasonCharacters))
    self.deliveryMode = deliveryMode
    self.requiredCapabilities = requiredCapabilities
    self.artifactIds = artifactIds
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .stableDistinct()
      .prefixArray(Self.maxArtifactIds)
    self.checkpoint = checkpoint
    self.context = context
    self.createdAtMillis = max(createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case handoffId = "handoff_id"
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case runId = "run_id"
    case parentRunId = "parent_run_id"
    case fromAgentId = "from_agent_id"
    case toAgentId = "to_agent_id"
    case returnToAgentId = "return_to_agent_id"
    case reason
    case deliveryMode = "delivery_mode"
    case requiredCapabilities = "required_capabilities"
    case artifactIds = "artifact_ids"
    case checkpoint
    case context
    case createdAtMillis = "created_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let runId = try container.decodeIfPresent(String.self, forKey: .runId) ?? ""
    let fromAgentId = try container.decodeIfPresent(String.self, forKey: .fromAgentId) ?? ""
    self.init(
      handoffId: try container.decodeIfPresent(String.self, forKey: .handoffId) ?? UUID().uuidString,
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      runId: runId,
      parentRunId: try container.decodeIfPresent(String.self, forKey: .parentRunId),
      fromAgentId: fromAgentId,
      toAgentId: try container.decodeIfPresent(String.self, forKey: .toAgentId) ?? "",
      returnToAgentId: try container.decodeIfPresent(String.self, forKey: .returnToAgentId),
      reason: try container.decodeIfPresent(String.self, forKey: .reason) ?? "",
      deliveryMode: try container.decodeIfPresent(AgentDeliveryMode.self, forKey: .deliveryMode) ?? .respond,
      requiredCapabilities: try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .requiredCapabilities) ?? [],
      artifactIds: try container.decodeIfPresent([String].self, forKey: .artifactIds) ?? [],
      checkpoint: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .checkpoint) ?? [:],
      context: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .context) ?? [:],
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? AgentControlPlaneClock.nowMillis()
    )
  }

  private static let maxIdCharacters = 512
  private static let maxReasonCharacters = 2_000
  private static let maxArtifactIds = 128
}

enum AgentHandoffState: String, Codable, CaseIterable, Identifiable {
  case requested = "REQUESTED"
  case active = "ACTIVE"
  case returned = "RETURNED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }
  var isTerminal: Bool { Self.terminalStates.contains(self) }

  static let terminalStates: Set<AgentHandoffState> = [.returned, .failed, .cancelled]

  static func fromWireValue(_ value: String?, fallback: AgentHandoffState = .failed) -> AgentHandoffState {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? fallback
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self), fallback: .failed)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentHandoffRecord: Codable, Equatable, Identifiable {
  var request: AgentHandoffRequest
  var state: AgentHandoffState
  var sourceMessageId: Int64
  var resultSummary: String
  var updatedAtMillis: Int64

  var id: String { request.handoffId }

  init(
    request: AgentHandoffRequest,
    state: AgentHandoffState,
    sourceMessageId: Int64 = 0,
    resultSummary: String = "",
    updatedAtMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) {
    self.request = request
    self.state = state
    self.sourceMessageId = max(sourceMessageId, 0)
    self.resultSummary = String(resultSummary.prefix(Self.maxResultCharacters))
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case request
    case state
    case sourceMessageId = "source_message_id"
    case resultSummary = "result_summary"
    case updatedAtMillis = "updated_at_millis"
  }

  private static let maxResultCharacters = 2_000
}

struct AgentHandoffMutation: Equatable {
  var record: AgentHandoffRecord
  var created: Bool
}

enum AgentHandoffLifecycle {
  static func stableId(runId: String, stepId: String, fromAgentId: String, toAgentId: String) -> String {
    let source = [runId, stepId, fromAgentId, toAgentId].joined(separator: "\u{001f}")
    return nameBasedUUID(source)
  }

  static func transition(current: AgentHandoffState, requested: AgentHandoffState) -> AgentHandoffState {
    if current.isTerminal {
      return current
    }
    switch requested {
    case .requested:
      return current
    case .active:
      return .active
    case .returned:
      return .returned
    case .failed:
      return .failed
    case .cancelled:
      return .cancelled
    }
  }

  private static func nameBasedUUID(_ name: String) -> String {
    var bytes = Array(Insecure.MD5.hash(data: Data(name.utf8)))
    bytes[6] = (bytes[6] & 0x0f) | 0x30
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    let uuid = UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5],
      bytes[6], bytes[7],
      bytes[8], bytes[9],
      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
    return uuid.uuidString.lowercased()
  }
}

struct AgentHandoffStoreError: Error, Equatable {
  var message: String
}

protocol AgentHandoffStore: AnyObject {
  func beginActive(_ request: AgentHandoffRequest, sourceMessageId: Int64) throws -> AgentHandoffMutation
  func finish(runId: String, sourceMessageId: Int64, state: AgentHandoffState, resultSummary: String) throws -> AgentHandoffRecord?
  func list() -> [AgentHandoffRecord]
  func forRun(_ runId: String) -> [AgentHandoffRecord]
  func active() -> [AgentHandoffRecord]
  func clear()
}

class BaseAgentHandoffStore: AgentHandoffStore {
  private let lock = NSRecursiveLock()
  private let clock: () -> Int64

  init(clock: @escaping () -> Int64 = AgentControlPlaneClock.nowMillis) {
    self.clock = clock
  }

  func readPersisted() -> [AgentHandoffRecord] {
    []
  }

  func writePersisted(_ records: [AgentHandoffRecord]) {}

  func clearPersisted() {}

  final func beginActive(_ request: AgentHandoffRequest, sourceMessageId: Int64 = 0) throws -> AgentHandoffMutation {
    lock.lock()
    defer { lock.unlock() }
    try requireNonBlank(request.handoffId, label: "Handoff id")
    try requireNonBlank(request.runId, label: "Handoff run id")
    try requireNonBlank(request.taskId, label: "Handoff task id")
    try requireNonBlank(request.fromAgentId, label: "Handoff source Agent")
    try requireNonBlank(request.toAgentId, label: "Handoff destination Agent")
    var records = readPersisted()
    if let existing = records.first(where: { $0.request.handoffId == request.handoffId }) {
      return AgentHandoffMutation(record: existing, created: false)
    }
    let record = AgentHandoffRecord(
      request: request,
      state: .active,
      sourceMessageId: sourceMessageId,
      updatedAtMillis: now()
    )
    records.append(record)
    writePersisted(bound(records))
    return AgentHandoffMutation(record: record, created: true)
  }

  final func finish(
    runId: String,
    sourceMessageId: Int64 = 0,
    state: AgentHandoffState,
    resultSummary: String = ""
  ) throws -> AgentHandoffRecord? {
    lock.lock()
    defer { lock.unlock() }
    guard state.isTerminal else {
      throw AgentHandoffStoreError(message: "A handoff can only finish in a terminal state")
    }
    let cleanRunId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    var records = readPersisted()
    guard let index = records.lastIndex(where: { record in
      record.request.runId == cleanRunId &&
        !record.state.isTerminal &&
        (sourceMessageId <= 0 || record.sourceMessageId == sourceMessageId)
    }) else {
      return nil
    }
    let current = records[index]
    let updated = AgentHandoffRecord(
      request: current.request,
      state: AgentHandoffLifecycle.transition(current: current.state, requested: state),
      sourceMessageId: current.sourceMessageId,
      resultSummary: resultSummary,
      updatedAtMillis: now()
    )
    records[index] = updated
    writePersisted(bound(records))
    return updated
  }

  final func list() -> [AgentHandoffRecord] {
    lock.lock()
    defer { lock.unlock() }
    return readPersisted()
  }

  final func forRun(_ runId: String) -> [AgentHandoffRecord] {
    let cleanRunId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    return list().filter { $0.request.runId == cleanRunId }
  }

  final func active() -> [AgentHandoffRecord] {
    list().filter { !$0.state.isTerminal }
  }

  final func clear() {
    lock.lock()
    defer { lock.unlock() }
    clearPersisted()
  }

  private func requireNonBlank(_ value: String, label: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentHandoffStoreError(message: "\(label) must not be blank")
    }
  }

  private func bound(_ records: [AgentHandoffRecord]) -> [AgentHandoffRecord] {
    Array(records.suffix(Self.maxRecords))
  }

  private func now() -> Int64 {
    max(clock(), 0)
  }

  private static let maxRecords = 1_000
}

final class InMemoryAgentHandoffStore: BaseAgentHandoffStore {
  private var document: String

  init(
    serialized: String = "[]",
    clock: @escaping () -> Int64 = AgentControlPlaneClock.nowMillis
  ) {
    self.document = serialized
    super.init(clock: clock)
  }

  override func readPersisted() -> [AgentHandoffRecord] {
    AgentHandoffJsonCodec.decode(document)
  }

  override func writePersisted(_ records: [AgentHandoffRecord]) {
    document = AgentHandoffJsonCodec.encode(records)
  }

  override func clearPersisted() {
    document = "[]"
  }

  func serializedSnapshot() -> String {
    document
  }
}

final class UserDefaultsAgentHandoffStore: BaseAgentHandoffStore {
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "galaxyssi_agent_handoffs_v1.records",
    clock: @escaping () -> Int64 = AgentControlPlaneClock.nowMillis
  ) {
    self.defaults = defaults
    self.key = key
    super.init(clock: clock)
  }

  override func readPersisted() -> [AgentHandoffRecord] {
    AgentHandoffJsonCodec.decode(defaults.string(forKey: key) ?? "[]")
  }

  override func writePersisted(_ records: [AgentHandoffRecord]) {
    defaults.set(AgentHandoffJsonCodec.encode(records), forKey: key)
  }

  override func clearPersisted() {
    defaults.removeObject(forKey: key)
  }
}

enum AgentHandoffJsonCodec {
  static func encode(_ records: [AgentHandoffRecord]) -> String {
    AgentMcpJSONCodec.stringify(.array(records.map { .object(recordObject($0)) }))
  }

  static func decode(_ raw: String) -> [AgentHandoffRecord] {
    guard let data = raw.data(using: .utf8),
      let values = try? JSONDecoder().decode([AgentMcpJSONValue].self, from: data) else {
      return []
    }
    return values.compactMap { value in
      guard case .object(let object) = value else {
        return nil
      }
      return decodeRecord(object)
    }
  }

  static func recordObject(_ record: AgentHandoffRecord) -> AgentMcpJSONObject {
    let request = record.request
    return [
      "handoff_id": .string(request.handoffId),
      "conversation_id": .string(request.conversationId),
      "task_id": .string(request.taskId),
      "run_id": .string(request.runId),
      "parent_run_id": .string(request.parentRunId),
      "from_agent_id": .string(request.fromAgentId),
      "to_agent_id": .string(request.toAgentId),
      "return_to_agent_id": .string(request.returnToAgentId),
      "reason": .string(request.reason),
      "delivery_mode": .string(request.deliveryMode.rawValue),
      "required_capabilities": .array(request.requiredCapabilities.map(\.rawValue).sorted().map(AgentMcpJSONValue.string)),
      "artifact_ids": .array(request.artifactIds.map(AgentMcpJSONValue.string)),
      "checkpoint": .object(request.checkpoint),
      "context": .object(request.context),
      "created_at_millis": .int(request.createdAtMillis),
      "state": .string(record.state.rawValue),
      "source_message_id": .int(record.sourceMessageId),
      "result_summary": .string(record.resultSummary),
      "updated_at_millis": .int(record.updatedAtMillis)
    ]
  }

  private static func decodeRecord(_ object: AgentMcpJSONObject) -> AgentHandoffRecord? {
    let handoffId = object.string("handoff_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let taskId = object.string("task_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let runId = object.string("run_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let fromAgentId = object.string("from_agent_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let toAgentId = object.string("to_agent_id").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !handoffId.isEmpty,
      !taskId.isEmpty,
      !runId.isEmpty,
      !fromAgentId.isEmpty,
      !toAgentId.isEmpty else {
      return nil
    }
    let request = AgentHandoffRequest(
      handoffId: handoffId,
      conversationId: object.string("conversation_id"),
      taskId: taskId,
      runId: runId,
      parentRunId: object.string("parent_run_id"),
      fromAgentId: fromAgentId,
      toAgentId: toAgentId,
      returnToAgentId: object.string("return_to_agent_id"),
      reason: object.string("reason"),
      deliveryMode: AgentDeliveryMode(rawValue: object.string("delivery_mode")) ?? .respond,
      requiredCapabilities: object.capabilitySet("required_capabilities"),
      artifactIds: object.stringArray("artifact_ids"),
      checkpoint: object.object("checkpoint") ?? [:],
      context: object.object("context") ?? [:],
      createdAtMillis: positiveOrNow(object.int64("created_at_millis"))
    )
    return AgentHandoffRecord(
      request: request,
      state: AgentHandoffState.fromWireValue(object.string("state"), fallback: .failed),
      sourceMessageId: object.int64("source_message_id"),
      resultSummary: object.string("result_summary"),
      updatedAtMillis: positiveOrNow(object.int64("updated_at_millis"))
    )
  }

  private static func positiveOrNow(_ value: Int64) -> Int64 {
    value > 0 ? value : AgentControlPlaneClock.nowMillis()
  }
}

enum AgentControlPlaneClock {
  static func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

private extension Dictionary where Key == String, Value == AgentMcpJSONValue {
  func stringArray(_ key: String) -> [String] {
    guard case .array(let values)? = self[key] else {
      return []
    }
    return values
      .compactMap(\.stringValue)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  func capabilitySet(_ key: String) -> Set<AgentCapability> {
    Set(stringArray(key).compactMap(AgentCapability.fromWireValue))
  }
}

private extension Array where Element == String {
  func stableDistinct() -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for item in self where seen.insert(item).inserted {
      result.append(item)
    }
    return result
  }

  func prefixArray(_ count: Int) -> [String] {
    Array(prefix(Swift.max(count, 0)))
  }
}
