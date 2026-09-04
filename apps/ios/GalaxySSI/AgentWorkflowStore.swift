import Combine
import Foundation

struct AgentWorkflow: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var goal: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64
  var runCount: Int
  var lastRunAtMillis: Int64

  init(
    id: String = UUID().uuidString.lowercased(),
    name: String,
    goal: String,
    createdAtMillis: Int64 = AgentWorkflowStoreClock.nowMillis(),
    updatedAtMillis: Int64 = AgentWorkflowStoreClock.nowMillis(),
    runCount: Int = 0,
    lastRunAtMillis: Int64 = 0
  ) {
    self.id = id
    self.name = name
    self.goal = goal
    self.createdAtMillis = createdAtMillis
    self.updatedAtMillis = updatedAtMillis
    self.runCount = max(0, runCount)
    self.lastRunAtMillis = max(0, lastRunAtMillis)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case goal
    case createdAtMillis = "created_at"
    case updatedAtMillis = "updated_at"
    case runCount = "run_count"
    case lastRunAtMillis = "last_run_at"
  }
}

struct AgentWorkflowTemplate: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var goal: String
}

enum AgentWorkflowStoreError: LocalizedError, Equatable {
  case required(String)
  case invalid(String)
  case persistence(String)

  var errorDescription: String? {
    switch self {
    case .required(let field): return "Workflow \(field) is required"
    case .invalid(let message): return message
    case .persistence(let message): return message
    }
  }
}

protocol AgentWorkflowStore: AnyObject {
  func list() -> [AgentWorkflow]
  func findById(_ id: String) -> AgentWorkflow?
  func find(_ name: String) -> AgentWorkflow?
  @discardableResult func save(name: String, goal: String) throws -> AgentWorkflow
  @discardableResult func delete(name: String) -> Int
  func markRun(id: String)
  func clear()
}

enum AgentWorkflowStoreClock {
  static func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

final class UserDefaultsAgentWorkflowStore: ObservableObject, AgentWorkflowStore {
  static let shared = UserDefaultsAgentWorkflowStore()

  static let maxItems = 100
  static let maxNameCharacters = 80
  static let maxGoalCharacters = 2_000

  @Published private(set) var workflows: [AgentWorkflow]

  private let defaults: UserDefaults
  private let storageKey = "galaxyssi.agent.workflows.v1"
  private let lock = NSRecursiveLock()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.workflows = Self.load(from: defaults, key: "galaxyssi.agent.workflows.v1")
  }

  func list() -> [AgentWorkflow] {
    lock.lock()
    defer { lock.unlock() }
    return workflows.sorted { left, right in
      if left.updatedAtMillis != right.updatedAtMillis {
        return left.updatedAtMillis > right.updatedAtMillis
      }
      return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
  }

  func findById(_ id: String) -> AgentWorkflow? {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanId.isEmpty else { return nil }
    lock.lock()
    defer { lock.unlock() }
    return workflows.first { $0.id == cleanId }
  }

  func find(_ name: String) -> AgentWorkflow? {
    let cleanName = Self.normalizeName(name)
    guard !cleanName.isEmpty else { return nil }
    lock.lock()
    defer { lock.unlock() }
    return workflows.first { Self.normalizeName($0.name) == cleanName }
      ?? workflows.first { Self.normalizeName($0.name).contains(cleanName) }
  }

  @discardableResult
  func save(name: String, goal: String) throws -> AgentWorkflow {
    let cleanName = Self.canonicalName(name).prefix(Self.maxNameCharacters).description
    let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxGoalCharacters).description
    try Self.validate(name: cleanName, goal: cleanGoal)

    lock.lock()
    defer { lock.unlock() }
    let now = AgentWorkflowStoreClock.nowMillis()
    let existing = workflows.first { Self.normalizeName($0.name) == Self.normalizeName(cleanName) }
    let next = AgentWorkflow(
      id: existing?.id ?? UUID().uuidString.lowercased(),
      name: cleanName,
      goal: cleanGoal,
      createdAtMillis: existing?.createdAtMillis ?? now,
      updatedAtMillis: now,
      runCount: existing?.runCount ?? 0,
      lastRunAtMillis: existing?.lastRunAtMillis ?? 0
    )
    let nextItems = Array(
      workflows
        .filter { $0.id != next.id && Self.normalizeName($0.name) != Self.normalizeName(next.name) }
        .appending(next)
        .sorted { $0.updatedAtMillis < $1.updatedAtMillis }
        .suffix(Self.maxItems)
    )
    try persist(nextItems)
    workflows = nextItems
    return next
  }

  @discardableResult
  func delete(name: String) -> Int {
    guard let match = find(name) else { return 0 }
    lock.lock()
    defer { lock.unlock() }
    let nextItems = workflows.filter { $0.id != match.id }
    guard nextItems.count != workflows.count else { return 0 }
    try? persist(nextItems)
    workflows = nextItems
    return 1
  }

  func markRun(id: String) {
    lock.lock()
    defer { lock.unlock() }
    guard workflows.contains(where: { $0.id == id }) else { return }
    let now = AgentWorkflowStoreClock.nowMillis()
    let nextItems = workflows.map { item in
      guard item.id == id else { return item }
      return AgentWorkflow(
        id: item.id,
        name: item.name,
        goal: item.goal,
        createdAtMillis: item.createdAtMillis,
        updatedAtMillis: now,
        runCount: item.runCount + 1,
        lastRunAtMillis: now
      )
    }
    try? persist(nextItems)
    workflows = nextItems
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    defaults.removeObject(forKey: storageKey)
    workflows = []
  }

  private func persist(_ items: [AgentWorkflow]) throws {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      defaults.set(try encoder.encode(items), forKey: storageKey)
    } catch {
      throw AgentWorkflowStoreError.persistence("Unable to save Agent workflows")
    }
  }

  private static func load(from defaults: UserDefaults, key: String) -> [AgentWorkflow] {
    guard let data = defaults.data(forKey: key),
          let decoded = try? JSONDecoder().decode([AgentWorkflow].self, from: data) else {
      return []
    }
    return Array(decoded.filter { !$0.name.isEmpty && !$0.goal.isEmpty }.suffix(maxItems))
  }

  private static func validate(name: String, goal: String) throws {
    guard !name.isEmpty else { throw AgentWorkflowStoreError.required("name") }
    guard !goal.isEmpty else { throw AgentWorkflowStoreError.required("goal") }
    let lowerGoal = goal.lowercased()
    guard !lowerGoal.hasPrefix("run workflow ") else {
      throw AgentWorkflowStoreError.invalid("Nested workflow execution is not allowed")
    }
    guard !lowerGoal.hasPrefix("run template ") else {
      throw AgentWorkflowStoreError.invalid("Nested template execution is not allowed")
    }
    let managementPrefixes = ["save workflow ", "create workflow ", "delete workflow ", "remove workflow "]
    guard !managementPrefixes.contains(where: lowerGoal.hasPrefix) else {
      throw AgentWorkflowStoreError.invalid("Workflow management commands cannot be saved as workflows")
    }
    let reserved = Set(["approve", "confirm", "pause", "resume", "cancel", "retry", "try again"])
    guard !reserved.contains(lowerGoal) else {
      throw AgentWorkflowStoreError.invalid("Task control commands cannot be saved as workflows")
    }
  }

  private static func canonicalName(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }

  private static func normalizeName(_ value: String) -> String {
    canonicalName(value)
      .lowercased()
  }
}

extension Array {
  fileprivate func appending(_ element: Element) -> [Element] {
    var copy = self
    copy.append(element)
    return copy
  }
}

enum AgentWorkflowTemplates {
  static let all: [AgentWorkflowTemplate] = [
    AgentWorkflowTemplate(id: "screen-briefing", name: "Screen Briefing", goal: "summarize screen"),
    AgentWorkflowTemplate(id: "save-screen", name: "Save Screen Knowledge", goal: "save screen to knowledge"),
    AgentWorkflowTemplate(id: "device-health", name: "Device Health", goal: "device status"),
    AgentWorkflowTemplate(id: "notification-review", name: "Notification Review", goal: "read notifications"),
    AgentWorkflowTemplate(id: "knowledge-overview", name: "Knowledge Overview", goal: "knowledge status"),
    AgentWorkflowTemplate(id: "permission-check", name: "Permission Check", goal: "check permissions")
  ]

  static func find(_ name: String) -> AgentWorkflowTemplate? {
    let clean = name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
      .lowercased()
    guard !clean.isEmpty else { return nil }
    return all.first { $0.id == clean || $0.name.lowercased() == clean }
      ?? all.first { $0.name.lowercased().contains(clean) }
  }
}

struct AgentWorkflowResolution: Equatable {
  var id: String
  var name: String
  var goal: String
  var isTemplate: Bool
  var workflowId: String?
}

enum AgentWorkflowResolver {
  static func resolve(
    _ reference: String,
    store: AgentWorkflowStore = UserDefaultsAgentWorkflowStore.shared
  ) -> AgentWorkflowResolution? {
    let clean = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    if let workflow = store.findById(clean) ?? store.find(clean) {
      return AgentWorkflowResolution(
        id: workflow.id,
        name: workflow.name,
        goal: workflow.goal,
        isTemplate: false,
        workflowId: workflow.id
      )
    }
    guard let template = AgentWorkflowTemplates.find(clean) else { return nil }
    return AgentWorkflowResolution(
      id: template.id,
      name: template.name,
      goal: template.goal,
      isTemplate: true,
      workflowId: nil
    )
  }

  static func defaultReference(store: AgentWorkflowStore = UserDefaultsAgentWorkflowStore.shared) -> String {
    store.list().first?.name ?? AgentWorkflowTemplates.all.first?.name ?? "Screen Briefing"
  }
}
