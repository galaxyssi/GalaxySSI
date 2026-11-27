import Foundation

// Synchronous, single-use handoff. Scratch may move between threads, but is never
// used concurrently. Closing during apply requests rollback; COMMIT linearizes
// against close under this small ownership lock.
final class AgentKnowledgePreparedSourceReplacement {
  struct Policy {
    let updatedAtMillis: Int64
    let itemKey: String
    let cloudAccess: AgentKnowledgeCloudAccess
    let agentAccess: AgentKnowledgeAgentAccess
    let allowedAgentIds: [String]
    init(_ item: AgentKnowledgeItem, key: String) {
      updatedAtMillis = item.updatedAtMillis; itemKey = key
      cloudAccess = item.cloudAccess; agentAccess = item.agentAccess; allowedAgentIds = item.allowedAgentIds
    }
  }
  let owner: AgentKnowledgeDatabase
  let source: String
  let revision: Int64
  let token: UInt64
  let policy: Policy?
  private let lock = NSLock()
  private enum State { case ready, applying, consumed, closed }
  private var state = State.ready, closeRequested = false
  private var stage: AgentKnowledgeSourceStaging?

  init(owner: AgentKnowledgeDatabase, stage: AgentKnowledgeSourceStaging, revision: Int64,
    token: UInt64, policy: Policy?) {
    self.owner = owner; self.stage = stage; source = stage.source
    self.revision = revision; self.token = token; self.policy = policy
  }
  deinit { close() }
  func claim(for database: AgentKnowledgeDatabase) throws -> AgentKnowledgeSourceStaging {
    lock.lock(); defer { lock.unlock() }
    guard owner === database else { throw AgentKnowledgeDatabaseError.preparedSourceOwnerMismatch }
    guard state == .ready, let stage else { throw AgentKnowledgeDatabaseError.sourceReplacementConsumed }
    state = .applying
    return stage
  }
  func checkActive() throws {
    lock.lock(); defer { lock.unlock() }
    guard state == .applying, !closeRequested else { throw CancellationError() }
    try Task.checkCancellation()
    guard owner.nativeFiles.readToken() == token else { throw CancellationError() }
  }
  func commitCanonical(_ commit: () throws -> Void) throws {
    lock.lock(); defer { lock.unlock() }
    guard state == .applying, !closeRequested else { throw CancellationError() }
    try Task.checkCancellation()
    guard owner.nativeFiles.readToken() == token else { throw CancellationError() }
    try commit()
    state = .consumed; stage = nil
  }
  func failed() {
    lock.lock(); let owned = stage; stage = nil; state = .consumed; lock.unlock()
    owned?.close()
  }
  func close() {
    lock.lock()
    if state == .applying { closeRequested = true; lock.unlock(); return }
    let owned = stage; stage = nil; state = .closed; lock.unlock()
    owned?.close()
  }
}
