import Foundation

protocol AgentConfirmationConsentStore {
  func isRemembered(consentKey: String) -> Bool
  func rememberedKeys() -> Set<String>
  func remember(consentKey: String)
  @discardableResult func forget(consentKey: String) -> Bool
  func clear()
}

final class AgentGrantBackedConfirmationConsentStore: AgentConfirmationConsentStore {
  private let grantStore: InMemoryAgentPermissionGrantStore
  private let subjectId: String

  init(
    grantStore: InMemoryAgentPermissionGrantStore = InMemoryAgentPermissionGrantStore(),
    subjectId: String = Self.defaultSubjectId
  ) {
    self.grantStore = grantStore
    self.subjectId = subjectId
  }

  func isRemembered(consentKey: String) -> Bool {
    guard let key = clean(consentKey) else { return false }
    return ((try? grantStore.authorize(permissionRequest(key)))?.granted) == true
  }

  func rememberedKeys() -> Set<String> {
    Set(grantStore.list(includeInactive: false)
      .filter { grant in
        grant.subjectType == .consequentialAction &&
          grant.subjectId == subjectId &&
          grant.scope == grant.action
      }
      .map(\.scope))
  }

  func remember(consentKey: String) {
    guard let key = clean(consentKey), !isRemembered(consentKey: key) else { return }
    _ = try? grantStore.grant(AgentPermissionGrant(
      subjectType: .consequentialAction,
      subjectId: subjectId,
      scope: key,
      action: key,
      issuer: .user,
      evidence: "user_confirmed_once",
      lifetime: .permanent
    ))
  }

  @discardableResult
  func forget(consentKey: String) -> Bool {
    guard let key = clean(consentKey) else { return false }
    let grantIds = grantStore.list(includeInactive: false)
      .filter { grant in
        grant.subjectType == .consequentialAction &&
          grant.subjectId == subjectId &&
          grant.scope == key &&
          grant.action == key
      }
      .map(\.grantId)
    var revoked = false
    for grantId in grantIds {
      let revocation = grantStore.revokeGrant(
        grantId: grantId,
        reason: "user_revoked_remembered_confirmation"
      )
      revoked = revoked || !revocation.revokedGrantIds.isEmpty
    }
    return revoked
  }

  func clear() {
    rememberedKeys().forEach { _ = forget(consentKey: $0) }
  }

  func serializedSnapshot() -> String {
    grantStore.serializedSnapshot()
  }

  private func permissionRequest(_ key: String) -> AgentPermissionRequest {
    AgentPermissionRequest(
      subjectType: .consequentialAction,
      subjectId: subjectId,
      scope: key,
      action: key
    )
  }

  private func clean(_ value: String) -> String? {
    value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  private static let defaultSubjectId = "signalasi-host"
}

final class UserDefaultsAgentConfirmationConsentStore: AgentConfirmationConsentStore {
  private let defaults: UserDefaults
  private let storageKey: String
  private let subjectId: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = "signalasi_confirmation_consent_grants_v1",
    subjectId: String = "signalasi-host",
    nowMillis: @escaping () -> Int64 = {
      Int64(Date().timeIntervalSince1970 * 1_000)
    }
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.subjectId = subjectId
    self.nowMillis = nowMillis
  }

  func isRemembered(consentKey: String) -> Bool {
    read { $0.isRemembered(consentKey: consentKey) }
  }

  func rememberedKeys() -> Set<String> {
    read { $0.rememberedKeys() }
  }

  func remember(consentKey: String) {
    mutate { $0.remember(consentKey: consentKey) }
  }

  @discardableResult
  func forget(consentKey: String) -> Bool {
    mutate { $0.forget(consentKey: consentKey) }
  }

  func clear() {
    mutate { $0.clear() }
  }

  private func read<T>(_ body: (AgentGrantBackedConfirmationConsentStore) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body(makeStore())
  }

  @discardableResult
  private func mutate<T>(_ body: (AgentGrantBackedConfirmationConsentStore) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    let store = makeStore()
    let result = body(store)
    defaults.set(store.serializedSnapshot(), forKey: storageKey)
    return result
  }

  private func makeStore() -> AgentGrantBackedConfirmationConsentStore {
    AgentGrantBackedConfirmationConsentStore(
      grantStore: InMemoryAgentPermissionGrantStore(
        serialized: defaults.string(forKey: storageKey) ?? "[]",
        nowMillis: nowMillis
      ),
      subjectId: subjectId
    )
  }
}
