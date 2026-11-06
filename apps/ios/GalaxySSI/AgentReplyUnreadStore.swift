import Foundation

extension Notification.Name {
  static let galaxySSIReplyUnreadDidChange = Notification.Name("galaxySSIReplyUnreadDidChange")
}

enum AgentReplyUnreadPolicy {
  static func token(_ message: ChatMessage) -> String? {
    guard message.contactId == "hermes", !message.isMine, !message.isSystem,
          !message.conversationId.isEmpty,
          [.delivered, .read, .local].contains(message.deliveryStatus),
          !message.remoteMessageId.hasPrefix("agent-stream-"),
          !["approval:", "remote-approval:", "agent-recovery:", "stale-connector:"].contains(where: message.remoteMessageId.hasPrefix),
          !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !message.richOutputJson.isEmpty else {
      return nil
    }
    return [message.turnId, message.remoteMessageId, message.id.uuidString]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
  }

  static func canRead(visible: Bool, active: Bool, focused: Bool) -> Bool {
    visible && active && focused
  }

  struct Boundary: Equatable {
    let conversationId: String
    let cursor: GalaxySSIChatHistoryCursor
  }

  static func boundary(conversationId: String, rendered: [ChatMessage], isAtLatest: Bool) -> Boundary? {
    guard isAtLatest, !conversationId.isEmpty,
          let cursor = rendered.lazy.filter({ $0.contactId == "hermes" && $0.conversationId == conversationId })
            .map(GalaxySSIChatHistoryCursor.init).max() else { return nil }
    return Boundary(conversationId: conversationId, cursor: cursor)
  }
}

// Store identifiers only. Shared locking keeps multiple iPad windows from losing updates.
final class AgentReplyUnreadStore {
  static let key = "galaxyssi.agent.reply-unread.v1"
  private static let lock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore

  private struct State: Codable, Equatable {
    var seen: [String: Set<String>] = [:]
    var pending: [String: Set<String>] = [:]
    var contactReadAt: [String: Date] = [:]
    var positions: [String: [String: GalaxySSIChatHistoryCursor]]?
  }

  init(defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.defaults = defaults
    self.secrets = secrets
  }

  func count(conversationId: String? = nil) -> Int {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let pending = load().pending
    if let conversationId { return pending[conversationId]?.count ?? 0 }
    return pending.values.reduce(0) { $0 + $1.count }
  }

  func contactReadAt(_ contactId: String) -> Date {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return load().contactReadAt[contactId] ?? .distantPast
  }

  func markContactRead(_ contactId: String, at date: Date) {
    update { $0.contactReadAt[contactId] = max($0.contactReadAt[contactId] ?? .distantPast, date) }
  }

  func record(_ message: ChatMessage, previous: ChatMessage?) {
    guard let token = AgentReplyUnreadPolicy.token(message) else { return }
    update { state in
      let conversation = message.conversationId
      guard state.seen[conversation, default: []].insert(token).inserted else { return }
      // Rehydrating or editing an already-final reply must not create another unread event.
      if previous?.conversationId != conversation || previous.flatMap(AgentReplyUnreadPolicy.token) != token {
        state.pending[conversation, default: []].insert(token)
        var positions = state.positions ?? [:]
        positions[conversation, default: [:]][token] = GalaxySSIChatHistoryCursor(message)
        state.positions = positions
      }
    }
  }

  func read(conversationId: String, rendered: [ChatMessage], through cursor: GalaxySSIChatHistoryCursor? = nil) {
    let tokens = Set(rendered.filter { $0.conversationId == conversationId }.compactMap(AgentReplyUnreadPolicy.token))
    guard !tokens.isEmpty || cursor != nil else { return }
    update { state in
      var cleared = tokens
      if let cursor, let positions = state.positions?[conversationId] {
        for (token, position) in positions where position <= cursor {
          cleared.insert(token)
        }
      }
      state.pending[conversationId]?.subtract(cleared)
      for token in cleared {
        state.positions?[conversationId]?.removeValue(forKey: token)
      }
    }
  }

  func hasLegacyPending(conversationId: String) -> Bool {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let state = load()
    let positions = state.positions?[conversationId]
    return state.pending[conversationId]?.contains(where: { positions?[$0] == nil }) == true
  }

  func readLegacyPage(conversationId: String, messages: [ChatMessage]) {
    let tokens = Set(messages.filter { $0.conversationId == conversationId }.compactMap(AgentReplyUnreadPolicy.token))
    guard !tokens.isEmpty else { return }
    update { state in
      let positions = state.positions?[conversationId]
      state.pending[conversationId]?.subtract(tokens.filter { positions?[$0] == nil })
    }
  }

  func remove(_ message: ChatMessage) {
    guard let token = AgentReplyUnreadPolicy.token(message) else { return }
    update {
      $0.pending[message.conversationId]?.remove(token)
      $0.positions?[message.conversationId]?.removeValue(forKey: token)
    }
  }

  func removeConversations(_ ids: Set<String>) {
    update { state in
      for id in ids {
        state.pending.removeValue(forKey: id)
        state.seen.removeValue(forKey: id)
        state.positions?.removeValue(forKey: id)
      }
    }
  }

  func clear() {
    update { $0 = State() }
  }

  func clearAgentReplies() {
    update { state in
      state.seen.removeAll()
      state.pending.removeAll()
      state.positions = nil
    }
  }

  private func update(_ mutation: (inout State) -> Void) {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var state = load()
    let before = state
    mutation(&state)
    guard state != before, let data = try? JSONEncoder().encode(state),
          GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: Self.key, secrets: secrets) else { return }
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .galaxySSIReplyUnreadDidChange, object: nil)
    }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: Self.key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
    return state
  }
}
