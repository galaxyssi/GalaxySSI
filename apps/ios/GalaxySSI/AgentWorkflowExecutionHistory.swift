import Foundation

enum AgentWorkflowExecutionSource: String, Codable, CaseIterable, Identifiable {
  case manual = "MANUAL"
  case schedule = "SCHEDULE"
  case event = "EVENT"
  case proactive = "PROACTIVE"

  var id: String { rawValue }
}

enum AgentWorkflowExecutionStatus: String, Codable, CaseIterable, Identifiable {
  case running = "RUNNING"
  case waitingConfirmation = "WAITING_CONFIRMATION"
  case waitingResponse = "WAITING_RESPONSE"
  case completed = "COMPLETED"
  case skipped = "SKIPPED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case blocked = "BLOCKED"

  var id: String { rawValue }
}

struct AgentWorkflowExecutionRecord: Codable, Equatable, Identifiable {
  static let maxIdentifierCharacters = 128
  static let maxWorkflowNameCharacters = 80
  static let maxResultSummaryCharacters = 2_000

  var id: String
  var workflowId: String
  var workflowName: String
  var source: AgentWorkflowExecutionSource
  var status: AgentWorkflowExecutionStatus
  var startedAtMillis: Int64
  var completedAtMillis: Int64
  var resultSummary: String

  init(
    id: String = UUID().uuidString,
    workflowId: String,
    workflowName: String,
    source: AgentWorkflowExecutionSource,
    status: AgentWorkflowExecutionStatus,
    startedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    completedAtMillis: Int64 = 0,
    resultSummary: String = ""
  ) throws {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanWorkflowId = workflowId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanWorkflowName = workflowName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
    let cleanSummary = resultSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanId.isEmpty && cleanId.count <= Self.maxIdentifierCharacters,
      !cleanWorkflowId.isEmpty && cleanWorkflowId.count <= Self.maxIdentifierCharacters,
      !cleanWorkflowName.isEmpty && cleanWorkflowName.count <= Self.maxWorkflowNameCharacters,
      cleanSummary.count <= Self.maxResultSummaryCharacters,
      startedAtMillis >= 0,
      completedAtMillis >= 0,
      completedAtMillis == 0 || completedAtMillis >= startedAtMillis else {
      throw AgentProactiveTaskError.invalid("Workflow execution fields are invalid")
    }
    self.id = cleanId
    self.workflowId = cleanWorkflowId
    self.workflowName = cleanWorkflowName
    self.source = source
    self.status = status
    self.startedAtMillis = startedAtMillis
    self.completedAtMillis = completedAtMillis
    self.resultSummary = cleanSummary
  }

  enum CodingKeys: String, CodingKey {
    case id
    case workflowId = "workflow_id"
    case workflowName = "workflow_name"
    case source
    case status
    case startedAtMillis = "started_at_millis"
    case completedAtMillis = "completed_at_millis"
    case resultSummary = "result_summary"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      workflowId: try container.decodeIfPresent(String.self, forKey: .workflowId) ?? "",
      workflowName: try container.decodeIfPresent(String.self, forKey: .workflowName) ?? "",
      source: try container.decode(AgentWorkflowExecutionSource.self, forKey: .source),
      status: try container.decode(AgentWorkflowExecutionStatus.self, forKey: .status),
      startedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .startedAtMillis) ?? 0,
      completedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0,
      resultSummary: try container.decodeIfPresent(String.self, forKey: .resultSummary) ?? ""
    )
  }
}

final class AgentWorkflowExecutionHistoryStore {
  static let defaultStorageKey = "galaxyssi_agent_workflow_execution_history"
  static let defaultRecentLimit = 20
  static let maxRecords = 500

  private let defaults: UserDefaults
  private let storageKey: String
  private let lock = NSRecursiveLock()
  private var records: [String: AgentWorkflowExecutionRecord]

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = AgentWorkflowExecutionHistoryStore.defaultStorageKey
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    let raw = defaults.string(forKey: storageKey) ?? "[]"
    let decoded = (try? JSONDecoder().decode([AgentWorkflowExecutionRecord].self, from: Data(raw.utf8))) ?? []
    self.records = decoded.reduce(into: [:]) { result, record in
      result[record.id] = record
    }
  }

  func upsert(_ record: AgentWorkflowExecutionRecord) throws {
    lock.lock()
    defer { lock.unlock() }
    records[record.id] = record
    trimAndPersistLocked()
  }

  func findById(_ id: String) -> AgentWorkflowExecutionRecord? {
    let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    lock.lock()
    defer { lock.unlock() }
    return records[clean]
  }

  func recent(_ limit: Int = AgentWorkflowExecutionHistoryStore.defaultRecentLimit) -> [AgentWorkflowExecutionRecord] {
    lock.lock()
    defer { lock.unlock() }
    return Array(records.values
      .sorted { left, right in
        if left.startedAtMillis != right.startedAtMillis {
          return left.startedAtMillis > right.startedAtMillis
        }
        return left.id > right.id
      }
      .prefix(max(limit, 0)))
  }

  func listAll() -> [AgentWorkflowExecutionRecord] {
    lock.lock()
    defer { lock.unlock() }
    return records.values.sorted { $0.startedAtMillis < $1.startedAtMillis }
  }

  @discardableResult
  func deleteForWorkflow(_ workflowId: String) -> Int {
    let clean = workflowId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return 0 }
    lock.lock()
    defer { lock.unlock() }
    let before = records.count
    records = records.filter { $0.value.workflowId != clean }
    guard before != records.count else { return 0 }
    persistLocked()
    return before - records.count
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    records.removeAll()
    defaults.removeObject(forKey: storageKey)
  }

  func exportRecords() -> [AgentWorkflowExecutionRecord] {
    listAll()
  }

  func replaceAll(_ incoming: [AgentWorkflowExecutionRecord]) throws {
    lock.lock()
    defer { lock.unlock() }
    records.removeAll()
    for record in incoming {
      records[record.id] = record
    }
    trimAndPersistLocked()
  }

  private func trimAndPersistLocked() {
    let ordered = records.values.sorted {
      if $0.startedAtMillis != $1.startedAtMillis {
        return $0.startedAtMillis < $1.startedAtMillis
      }
      return $0.id < $1.id
    }
    records = Dictionary(uniqueKeysWithValues: ordered.suffix(Self.maxRecords).map { ($0.id, $0) })
    persistLocked()
  }

  private func persistLocked() {
    let ordered = records.values.sorted {
      if $0.startedAtMillis != $1.startedAtMillis {
        return $0.startedAtMillis < $1.startedAtMillis
      }
      return $0.id < $1.id
    }
    guard let data = try? JSONEncoder().encode(ordered) else { return }
    defaults.set(String(decoding: data, as: UTF8.self), forKey: storageKey)
  }
}
