import Foundation

final class AgentConversationalTeamStore {
  static let changed = Notification.Name("galaxyssi.conversation-team.changed")
  private static let lock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  let owner: String
  private var namespace: String { "galaxyssi.conversation-team.v1." + AgentTurnReceiptEvidence.hash(owner) + "." }
  private var material: String { namespace + "material" }
  init(owner: String, defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore) {
    self.owner = owner; self.defaults = defaults; self.secrets = secrets
  }
  private func row(_ conversation: String) -> String { namespace + AgentTurnReceiptEvidence.hash(conversation) }
  private func valid(_ conversation: String) -> Bool {
    !owner.isBlank && owner.utf8.count <= 512 && !conversation.isBlank && conversation.utf8.count <= 512
  }
  func read(_ conversation: String) throws -> AgentConversationalTeamJob? {
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard valid(conversation), !defaults.bool(forKey: row(conversation) + ".deleted") else { throw AgentConversationalTeamJob.Failure.stale }
    let key = row(conversation)
    guard GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: key) else { return nil }
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, keyMaterialKey: material, secrets: secrets),
      data.count <= 524_288, let job = try? JSONDecoder().decode(AgentConversationalTeamJob.self, from: data),
      job.valid, job.conversation == conversation else { throw AgentConversationalTeamJob.Failure.unavailable }
    return job
  }
  func jobs() throws -> [AgentConversationalTeamJob] {
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard !owner.isBlank else { throw AgentConversationalTeamJob.Failure.invalid }
    var result: [AgentConversationalTeamJob] = []
    for key in GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: namespace).sorted() {
      guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, keyMaterialKey: material, secrets: secrets),
        data.count <= 524_288, let job = try? JSONDecoder().decode(AgentConversationalTeamJob.self, from: data),
        job.valid, row(job.conversation) == key else { throw AgentConversationalTeamJob.Failure.unavailable }
      if !defaults.bool(forKey: key + ".deleted") { result.append(job) }
    }
    return result
  }
  func replace(_ job: AgentConversationalTeamJob, expected: AgentConversationalTeamJob?) throws {
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard job.valid, valid(job.conversation), try read(job.conversation) == expected else { throw AgentConversationalTeamJob.Failure.stale }
    if let expected {
      if job.id != expected.id {
        guard !expected.active, job.state == .queued else { throw AgentConversationalTeamJob.Failure.stale }
      } else {
        guard expected.active, job.objective == expected.objective, job.route == expected.route,
          job.revision == expected.revision + 1, job.calls >= expected.calls else { throw AgentConversationalTeamJob.Failure.stale }
        guard expected.state == .queued ? [.running, .stopped].contains(job.state) : job.state != .queued else {
          throw AgentConversationalTeamJob.Failure.stale
        }
        if job.state == .running {
          guard job.calls == expected.calls + (expected.state == .running ? 1 : 0) else { throw AgentConversationalTeamJob.Failure.stale }
        } else if job.calls != expected.calls { throw AgentConversationalTeamJob.Failure.stale }
      }
    } else if job.state != .queued { throw AgentConversationalTeamJob.Failure.stale }
    let data = try JSONEncoder().encode(job)
    guard data.count <= 524_288, GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults,
      key: row(job.conversation), keyMaterialKey: material, secrets: secrets) else { throw AgentConversationalTeamJob.Failure.unavailable }
    DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
  }
  func retire(_ expected: AgentConversationalTeamJob) throws {
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard !expected.active, try read(expected.conversation) == expected else { throw AgentConversationalTeamJob.Failure.stale }
    GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: row(expected.conversation))
  }
  func remove(_ conversation: String) {
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard valid(conversation) else { return }
    defaults.set(true, forKey: row(conversation) + ".deleted")
    GalaxySSIEncryptedUserDefaultsStore.remove(defaults: defaults, key: row(conversation))
    DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
  }
  static func destroyAll(defaults: UserDefaults, secrets: GalaxySSISecretStore) {
    lock.lock(); defer { lock.unlock() }
    let root = "galaxyssi.conversation-team.v1."
    let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(root) }
    let owners = Set(keys.map { String($0.dropFirst(root.count).prefix(64)) }.filter { MqttRouteProtocol.hex($0, count: 64) })
    for key in keys { defaults.removeObject(forKey: key) }
    for owner in owners { GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: root + owner + ".material", secrets: secrets) }
  }
}
