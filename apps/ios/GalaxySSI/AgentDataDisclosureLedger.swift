import CryptoKit
import Foundation

enum AgentDisclosedDataKind: String, Codable, CaseIterable, Hashable, Identifiable {
  case messageText = "message_text"
  case conversationHistory = "conversation_history"
  case systemInstructions = "system_instructions"
  case toolOutput = "tool_output"
  case screenContext = "screen_context"
  case memoryContext = "memory_context"
  case knowledgeContext = "knowledge_context"
  case deviceContext = "device_context"
  case image = "image"
  case audio = "audio"
  case video = "video"
  case document = "document"
  case otherFile = "other_file"

  var id: String { rawValue }
}

enum AgentDisclosureProtection: String, Codable, CaseIterable, Hashable, Identifiable {
  case onDevice = "on_device"
  case signalE2EE = "signal_e2ee"
  case tls = "tls"

  var id: String { rawValue }
}

enum AgentDisclosureStatus: String, Codable, CaseIterable, Hashable, Identifiable {
  case preparing = "preparing"
  case queued = "queued"
  case sent = "sent"
  case blocked = "blocked"
  case failed = "failed"

  var id: String { rawValue }
}

struct AgentDataDisclosureRecord: Codable, Equatable, Identifiable {
  var eventId: String
  var destinationId: String
  var destinationTitle: String
  var providerId: String
  var modelId: String
  var location: AgentResourceLocation
  var trust: AgentResourceTrust
  var protection: AgentDisclosureProtection
  var purpose: String
  var dataKinds: Set<AgentDisclosedDataKind>
  var textCharacters: Int
  var attachmentCount: Int
  var attachmentBytes: Int64
  var conversationIdHash: String
  var taskIdHash: String
  var turnIdHash: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64
  var status: AgentDisclosureStatus
  var failureReason: String

  var id: String { eventId }

  init(
    eventId: String = UUID().uuidString,
    destinationId: String,
    destinationTitle: String,
    providerId: String = "",
    modelId: String = "",
    location: AgentResourceLocation,
    trust: AgentResourceTrust,
    protection: AgentDisclosureProtection,
    purpose: String,
    dataKinds: Set<AgentDisclosedDataKind>,
    textCharacters: Int = 0,
    attachmentCount: Int = 0,
    attachmentBytes: Int64 = 0,
    conversationIdHash: String = "",
    taskIdHash: String = "",
    turnIdHash: String = "",
    createdAtMillis: Int64 = AgentDataDisclosureLedger.nowMillis(),
    updatedAtMillis: Int64? = nil,
    status: AgentDisclosureStatus = .preparing,
    failureReason: String = ""
  ) {
    let cleanDestinationId = destinationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanTitle = destinationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(!cleanDestinationId.isEmpty, "Disclosure destination is required")
    precondition(!cleanTitle.isEmpty, "Disclosure destination title is required")

    self.eventId = eventId
    self.destinationId = cleanDestinationId
    self.destinationTitle = cleanTitle
    self.providerId = String(providerId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    self.modelId = String(modelId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    self.location = location
    self.trust = trust
    self.protection = protection
    self.purpose = String(purpose.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    self.dataKinds = dataKinds
    self.textCharacters = max(textCharacters, 0)
    self.attachmentCount = max(attachmentCount, 0)
    self.attachmentBytes = max(attachmentBytes, 0)
    self.conversationIdHash = conversationIdHash
    self.taskIdHash = taskIdHash
    self.turnIdHash = turnIdHash
    self.createdAtMillis = max(createdAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis ?? createdAtMillis, 0)
    self.status = status
    self.failureReason = String(failureReason.prefix(InMemoryAgentDataDisclosureStore.maxFailureReasonCharacters))
  }

  enum CodingKeys: String, CodingKey {
    case eventId = "event_id"
    case destinationId = "destination_id"
    case destinationTitle = "destination_title"
    case providerId = "provider_id"
    case modelId = "model_id"
    case location
    case trust
    case protection
    case purpose
    case dataKinds = "data_kinds"
    case textCharacters = "text_characters"
    case attachmentCount = "attachment_count"
    case attachmentBytes = "attachment_bytes"
    case conversationIdHash = "conversation_id_hash"
    case taskIdHash = "task_id_hash"
    case turnIdHash = "turn_id_hash"
    case createdAtMillis = "created_at_ms"
    case updatedAtMillis = "updated_at_ms"
    case status
    case failureReason = "failure_reason"
  }
}

struct AgentDisclosureTicket: Codable, Equatable {
  var eventId: String
  var allowed: Bool

  enum CodingKeys: String, CodingKey {
    case eventId = "event_id"
    case allowed
  }
}

struct AgentDataDisclosureSummary: Codable, Equatable {
  var total: Int
  var cloud: Int
  var trustedDesktop: Int
  var blocked: Int
  var destinations: Int

  enum CodingKeys: String, CodingKey {
    case total
    case cloud
    case trustedDesktop = "trusted_desktop"
    case blocked
    case destinations
  }
}

struct AgentDataDisclosureBlockedError: LocalizedError, Equatable {
  var destination: String

  var errorDescription: String? {
    "Sharing with \(destination) is blocked by the privacy dashboard."
  }
}

struct AgentDataDisclosureCloudDestination: Equatable {
  var contactId: String
  var galaxySSIId: String
  var providerId: String
  var modelId: String
  var endpoint: String
  var displayName: String
  var name: String

  init(
    contactId: String = "",
    galaxySSIId: String = "",
    providerId: String = "",
    modelId: String = "",
    endpoint: String = "",
    displayName: String = "",
    name: String = ""
  ) {
    self.contactId = contactId
    self.galaxySSIId = galaxySSIId
    self.providerId = providerId
    self.modelId = modelId
    self.endpoint = endpoint
    self.displayName = displayName
    self.name = name
  }

  init(contact: GalaxySSIContact) {
    let model = contact.selectedCloudModel
    self.init(
      contactId: contact.id,
      galaxySSIId: contact.galaxySSIId,
      providerId: contact.cloudProvider.ifBlank(model?.provider ?? ""),
      modelId: model?.modelId ?? "",
      endpoint: model?.endpoint ?? "",
      displayName: contact.displayName,
      name: contact.name
    )
  }
}

struct AgentDataDisclosureAttachment: Equatable {
  var displayName: String
  var mimeType: String
  var sizeBytes: Int64

  init(displayName: String, mimeType: String, sizeBytes: Int64) {
    self.displayName = displayName
    self.mimeType = mimeType
    self.sizeBytes = max(sizeBytes, 0)
  }

  init(_ attachment: GalaxySSIDraftAttachment) {
    self.init(
      displayName: attachment.displayName,
      mimeType: attachment.mimeType,
      sizeBytes: Int64(attachment.sizeBytes)
    )
  }
}

protocol AgentDataDisclosureStore: AnyObject {
  func append(_ record: AgentDataDisclosureRecord)
  func update(eventId: String, status: AgentDisclosureStatus, failureReason: String)
  func list(limit: Int) -> [AgentDataDisclosureRecord]
  func find(eventId: String) -> AgentDataDisclosureRecord?
  func clearHistory()
  func blockedDestinationIds() -> Set<String>
  func setDestinationBlocked(destinationId: String, blocked: Bool)
}

extension AgentDataDisclosureStore {
  func update(eventId: String, status: AgentDisclosureStatus) {
    update(eventId: eventId, status: status, failureReason: "")
  }

  func list() -> [AgentDataDisclosureRecord] {
    list(limit: 100)
  }
}

final class InMemoryAgentDataDisclosureStore: AgentDataDisclosureStore {
  static let maxRecords = 1_000
  static let maxListLimit = 250
  static let maxFailureReasonCharacters = 240

  private let lock = NSLock()
  private var records: [AgentDataDisclosureRecord] = []
  private var blockedIds: Set<String> = []

  func append(_ record: AgentDataDisclosureRecord) {
    lock.lock()
    defer { lock.unlock() }
    records.append(record)
    if records.count > Self.maxRecords {
      records.removeFirst(records.count - Self.maxRecords)
    }
  }

  func update(eventId: String, status: AgentDisclosureStatus, failureReason: String) {
    lock.lock()
    defer { lock.unlock() }
    guard let index = records.lastIndex(where: { $0.eventId == eventId }) else { return }
    records[index].status = status
    records[index].failureReason = String(failureReason.prefix(Self.maxFailureReasonCharacters))
    records[index].updatedAtMillis = AgentDataDisclosureLedger.nowMillis()
  }

  func list(limit: Int = 100) -> [AgentDataDisclosureRecord] {
    lock.lock()
    defer { lock.unlock() }
    return Array(records.reversed().prefix(Self.boundedListLimit(limit)))
  }

  func find(eventId: String) -> AgentDataDisclosureRecord? {
    lock.lock()
    defer { lock.unlock() }
    return records.last { $0.eventId == eventId }
  }

  func clearHistory() {
    lock.lock()
    defer { lock.unlock() }
    records.removeAll()
  }

  func blockedDestinationIds() -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return blockedIds
  }

  func setDestinationBlocked(destinationId: String, blocked: Bool) {
    let normalized = destinationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    if blocked {
      blockedIds.insert(normalized)
    } else {
      blockedIds.remove(normalized)
    }
  }

  static func boundedListLimit(_ limit: Int) -> Int {
    min(max(limit, 1), maxListLimit)
  }
}

final class FileAgentDataDisclosureStore: AgentDataDisclosureStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let lock = NSLock()

  init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  static func destroyPersistentStore(
    fileURL: URL = AgentDataDisclosureStorePaths.ledgerURL(),
    fileManager: FileManager = .default
  ) {
    try? fileManager.removeItem(at: fileURL)
    let directory = fileURL.deletingLastPathComponent()
    if let entries = try? fileManager.contentsOfDirectory(atPath: directory.path), entries.isEmpty {
      try? fileManager.removeItem(at: directory)
    }
  }

  func append(_ record: AgentDataDisclosureRecord) {
    lock.lock()
    defer { lock.unlock() }
    var document = loadUnlocked()
    document.records.append(record)
    document.records = Array(document.records.suffix(InMemoryAgentDataDisclosureStore.maxRecords))
    saveUnlocked(document)
  }

  func update(eventId: String, status: AgentDisclosureStatus, failureReason: String) {
    lock.lock()
    defer { lock.unlock() }
    var document = loadUnlocked()
    guard let index = document.records.lastIndex(where: { $0.eventId == eventId }) else { return }
    document.records[index].status = status
    document.records[index].failureReason = String(failureReason.prefix(InMemoryAgentDataDisclosureStore.maxFailureReasonCharacters))
    document.records[index].updatedAtMillis = AgentDataDisclosureLedger.nowMillis()
    saveUnlocked(document)
  }

  func list(limit: Int = 100) -> [AgentDataDisclosureRecord] {
    lock.lock()
    defer { lock.unlock() }
    return Array(loadUnlocked().records.reversed().prefix(InMemoryAgentDataDisclosureStore.boundedListLimit(limit)))
  }

  func find(eventId: String) -> AgentDataDisclosureRecord? {
    lock.lock()
    defer { lock.unlock() }
    return loadUnlocked().records.last { $0.eventId == eventId }
  }

  func clearHistory() {
    lock.lock()
    defer { lock.unlock() }
    var document = loadUnlocked()
    document.records.removeAll()
    saveUnlocked(document)
  }

  func blockedDestinationIds() -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return Set(loadUnlocked().blockedDestinationIds)
  }

  func setDestinationBlocked(destinationId: String, blocked: Bool) {
    let normalized = destinationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    var document = loadUnlocked()
    var ids = Set(document.blockedDestinationIds)
    if blocked {
      ids.insert(normalized)
    } else {
      ids.remove(normalized)
    }
    document.blockedDestinationIds = ids.sorted()
    saveUnlocked(document)
  }

  private func loadUnlocked() -> AgentDataDisclosureDocument {
    guard fileManager.fileExists(atPath: fileURL.path),
          let data = try? Data(contentsOf: fileURL) else {
      return AgentDataDisclosureDocument()
    }
    if let document = try? decoder.decode(AgentDataDisclosureDocument.self, from: data) {
      return document.normalized()
    }
    if let records = try? decoder.decode([AgentDataDisclosureRecord].self, from: data) {
      return AgentDataDisclosureDocument(records: Array(records.suffix(InMemoryAgentDataDisclosureStore.maxRecords)))
    }
    return AgentDataDisclosureDocument()
  }

  private func saveUnlocked(_ document: AgentDataDisclosureDocument) {
    do {
      let directory = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try encoder.encode(document.normalized())
      try data.write(to: fileURL, options: .atomic)
      setProtectedStorageAttributes(directory: directory)
    } catch {
      // Privacy dashboard persistence must not interrupt the model request path.
    }
  }

  private func setProtectedStorageAttributes(directory: URL) {
    #if os(iOS)
    try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
    try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
    #endif
  }
}

struct AgentDataDisclosureStorePaths: Equatable {
  static func applicationSupportRootURL(fileManager: FileManager = .default) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GalaxySSI", isDirectory: true)
  }

  static func ledgerURL(rootURL: URL = applicationSupportRootURL()) -> URL {
    rootURL
      .appendingPathComponent("AgentDataDisclosure", isDirectory: true)
      .appendingPathComponent("agent-data-disclosure-ledger.json")
  }
}

enum AgentDataDisclosureLedger {
  static func beginCloudRequest(
    store: AgentDataDisclosureStore,
    destination: AgentDataDisclosureCloudDestination,
    text: String,
    historyCount: Int = 0,
    systemInstructions: Bool = false,
    toolOutput: Bool = false,
    purpose: String,
    attachments: [AgentDataDisclosureAttachment] = [],
    conversationId: String = "",
    taskId: String = "",
    turnId: String = ""
  ) -> AgentDisclosureTicket {
    let providerId = destination.providerId.ifBlank("custom")
    let contactId = destination.contactId.ifBlank(destination.galaxySSIId)
    let destinationId = contactId.ifBlank("cloud:\(providerId):\(destination.modelId)")
    let title = destination.displayName
      .ifBlank(destination.name)
      .ifBlank(providerId)
      .ifBlank(destination.modelId)
      .ifBlank("Cloud model")
    let localNetwork = isPrivateEndpoint(destination.endpoint)
    let attachmentKinds = Set(attachments.map {
      AgentDataDisclosureClassifier.attachmentKind(mimeType: $0.mimeType, displayName: $0.displayName)
    })
    let record = AgentDataDisclosureRecord(
      destinationId: destinationId,
      destinationTitle: title,
      providerId: providerId,
      modelId: destination.modelId,
      location: localNetwork ? .privateNetwork : .cloud,
      trust: localNetwork ? .privateConfigured : .cloudConfigured,
      protection: .tls,
      purpose: purpose,
      dataKinds: AgentDataDisclosureClassifier.classifyText(
        text: text,
        includeHistory: historyCount > 1,
        includeSystemInstructions: systemInstructions,
        includeToolOutput: toolOutput
      ).union(attachmentKinds),
      textCharacters: text.count,
      attachmentCount: attachments.count,
      attachmentBytes: attachments.reduce(Int64(0)) { $0 + max($1.sizeBytes, 0) },
      conversationIdHash: disclosureHash(conversationId),
      taskIdHash: disclosureHash(taskId),
      turnIdHash: disclosureHash(turnId)
    )
    return begin(store: store, record: record)
  }

  static func beginDesktopRequest(
    store: AgentDataDisclosureStore,
    contactId: String,
    desktopId: String = "",
    providerId: String = "",
    title: String = "",
    text: String,
    attachments: [AgentDataDisclosureAttachment] = [],
    conversationId: String = "",
    taskId: String = "",
    turnId: String = ""
  ) -> AgentDisclosureTicket {
    let destinationId = contactId.ifBlank(desktopId).ifBlank(providerId).ifBlank("desktop-agent")
    let displayTitle = title.ifBlank(providerId).ifBlank(destinationId)
    let attachmentKinds = Set(attachments.map {
      AgentDataDisclosureClassifier.attachmentKind(mimeType: $0.mimeType, displayName: $0.displayName)
    })
    let record = AgentDataDisclosureRecord(
      destinationId: destinationId,
      destinationTitle: displayTitle,
      providerId: providerId,
      location: .trustedDesktop,
      trust: .verifiedPaired,
      protection: .signalE2EE,
      purpose: "Agent task",
      dataKinds: AgentDataDisclosureClassifier.classifyText(text: text).union(attachmentKinds),
      textCharacters: text.count,
      attachmentCount: attachments.count,
      attachmentBytes: attachments.reduce(Int64(0)) { $0 + max($1.sizeBytes, 0) },
      conversationIdHash: disclosureHash(conversationId),
      taskIdHash: disclosureHash(taskId),
      turnIdHash: disclosureHash(turnId)
    )
    return begin(store: store, record: record)
  }

  static func update(
    store: AgentDataDisclosureStore,
    ticket: AgentDisclosureTicket,
    status: AgentDisclosureStatus,
    failureReason: String = ""
  ) {
    store.update(eventId: ticket.eventId, status: status, failureReason: failureReason)
  }

  static func summary(_ records: [AgentDataDisclosureRecord]) -> AgentDataDisclosureSummary {
    AgentDataDisclosureSummary(
      total: records.count,
      cloud: records.filter { $0.location == .cloud }.count,
      trustedDesktop: records.filter { $0.location == .trustedDesktop }.count,
      blocked: records.filter { $0.status == .blocked }.count,
      destinations: Set(records.map(\.destinationId)).count
    )
  }

  static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }

  private static func begin(
    store: AgentDataDisclosureStore,
    record: AgentDataDisclosureRecord
  ) -> AgentDisclosureTicket {
    let blocked = store.blockedDestinationIds().contains(record.destinationId)
    let stored = blocked
      ? AgentDataDisclosureRecord(
        eventId: record.eventId,
        destinationId: record.destinationId,
        destinationTitle: record.destinationTitle,
        providerId: record.providerId,
        modelId: record.modelId,
        location: record.location,
        trust: record.trust,
        protection: record.protection,
        purpose: record.purpose,
        dataKinds: record.dataKinds,
        textCharacters: record.textCharacters,
        attachmentCount: record.attachmentCount,
        attachmentBytes: record.attachmentBytes,
        conversationIdHash: record.conversationIdHash,
        taskIdHash: record.taskIdHash,
        turnIdHash: record.turnIdHash,
        createdAtMillis: record.createdAtMillis,
        updatedAtMillis: record.updatedAtMillis,
        status: .blocked,
        failureReason: "Destination blocked by the privacy dashboard"
      )
      : record
    store.append(stored)
    return AgentDisclosureTicket(eventId: stored.eventId, allowed: !blocked)
  }

  private static func isPrivateEndpoint(_ endpoint: String) -> Bool {
    let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    return normalized.contains("127.0.0.1")
      || normalized.contains("localhost")
      || normalized.contains("192.168.")
      || normalized.contains("10.")
      || (16...31).contains { normalized.contains("172.\($0).") }
  }

  private static func disclosureHash(_ value: String) -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return "" }
    return SHA256.hash(data: Data(clean.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

enum AgentDataDisclosureClassifier {
  static func classifyText(
    text: String,
    includeHistory: Bool = false,
    includeSystemInstructions: Bool = false,
    includeToolOutput: Bool = false
  ) -> Set<AgentDisclosedDataKind> {
    var kinds = Set<AgentDisclosedDataKind>()
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      kinds.insert(.messageText)
    }
    if includeHistory {
      kinds.insert(.conversationHistory)
    }
    if includeSystemInstructions {
      kinds.insert(.systemInstructions)
    }
    if includeToolOutput {
      kinds.insert(.toolOutput)
    }

    let normalized = text.lowercased()
    if normalized.contains("screen_context")
      || normalized.contains("current screen")
      || normalized.contains("screen tree") {
      kinds.insert(.screenContext)
    }
    if normalized.contains("memory context")
      || normalized.contains("durable memory")
      || normalized.contains("recalled memory") {
      kinds.insert(.memoryContext)
    }
    if normalized.contains("knowledge context")
      || normalized.contains("knowledge source")
      || normalized.contains("retrieved evidence") {
      kinds.insert(.knowledgeContext)
    }
    if normalized.contains("device context")
      || normalized.contains("device status")
      || normalized.contains("battery_percent") {
      kinds.insert(.deviceContext)
    }
    return kinds
  }

  static func attachmentKind(mimeType: String, displayName: String) -> AgentDisclosedDataKind {
    let mime = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let ext = displayName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: ".")
      .last
      .map { String($0).lowercased() } ?? ""

    if mime.hasPrefix("image/") {
      return .image
    }
    if mime.hasPrefix("audio/") {
      return .audio
    }
    if mime.hasPrefix("video/") {
      return .video
    }
    if mime.hasPrefix("text/") || documentExtensions.contains(ext) {
      return .document
    }
    return .otherFile
  }

  private static let documentExtensions: Set<String> = [
    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "txt", "md"
  ]
}

private struct AgentDataDisclosureDocument: Codable, Equatable {
  var records: [AgentDataDisclosureRecord]
  var blockedDestinationIds: [String]

  init(records: [AgentDataDisclosureRecord] = [], blockedDestinationIds: [String] = []) {
    self.records = records
    self.blockedDestinationIds = blockedDestinationIds
  }

  enum CodingKeys: String, CodingKey {
    case records
    case blockedDestinationIds = "blocked_destination_ids"
  }

  func normalized() -> AgentDataDisclosureDocument {
    AgentDataDisclosureDocument(
      records: Array(records.suffix(InMemoryAgentDataDisclosureStore.maxRecords)),
      blockedDestinationIds: Set(
        blockedDestinationIds
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      ).sorted()
    )
  }
}
