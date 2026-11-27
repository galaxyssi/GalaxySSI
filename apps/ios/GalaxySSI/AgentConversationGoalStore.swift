import Foundation

final class AgentConversationGoalStore {
  static let changed = Notification.Name("galaxyssi.conversation_goal.changed")
  private static let lock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  let owner: String
  private var namespace: String { "galaxyssi.conversation-goal.v1." + AgentTurnReceiptEvidence.hash(owner) + "." }
  private var material: String { namespace + "material" }
  init(owner: String, defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore) {
    self.owner = owner; self.defaults = defaults; self.secrets = secrets
  }
  private func row(_ conversation: String) -> String { namespace + AgentTurnReceiptEvidence.hash(conversation) }
  private func valid(_ conversation: String) -> Bool {
    !owner.isBlank && owner.utf8.count <= 512 && !conversation.isBlank && conversation.utf8.count <= 512
  }
  func read(_ conversation: String) throws -> AgentConversationGoal? {
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard valid(conversation) else { throw AgentConversationGoal.Failure.invalid }
    let key = row(conversation)
    guard !defaults.bool(forKey: key + ".deleted") else { throw AgentConversationGoal.Failure.stale }
    guard GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: key) else { return nil }
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, keyMaterialKey: material, secrets: secrets),
      data.count <= 1_048_576, let goal = try? JSONDecoder().decode(AgentConversationGoal.self, from: data),
      goal.valid, goal.conversation == conversation else { throw AgentConversationGoal.Failure.unavailable }
    return goal
  }
  func replace(_ goal: AgentConversationGoal, expected: AgentConversationGoal?) throws {
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard goal.valid, valid(goal.conversation), try read(goal.conversation) == expected else { throw AgentConversationGoal.Failure.stale }
    if let expected {
      guard goal.id == expected.id || expected.terminal else { throw AgentConversationGoal.Failure.stale }
      if goal.id == expected.id {
        guard goal.objective == expected.objective, goal.route == expected.route,
          goal.revision > expected.revision, goal.generation >= expected.generation else { throw AgentConversationGoal.Failure.stale }
      }
    }
    let data = try JSONEncoder().encode(goal)
    guard data.count <= 1_048_576, GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults,
      key: row(goal.conversation), keyMaterialKey: material, secrets: secrets) else { throw AgentConversationGoal.Failure.unavailable }
    DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
  }
  func remove(_ conversation: String) {
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard valid(conversation) else { return }
    defaults.set(true, forKey: row(conversation) + ".deleted")
    GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: row(conversation))
  }
}
