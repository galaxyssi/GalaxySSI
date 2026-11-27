import Foundation
import SQLite3

// Read existing account/rows only. Never instantiate a Store, create an identity,
// migrate a database, populate an index or create a missing encryption key.
struct AgentIOSOriginalPageArchiveOwner {
  private struct State: Decodable {
    struct Profile: Decodable { var identityFingerprint: String }
    var profile: Profile
    var agentSafetySettings: AgentSafetySettings
  }
  var defaults: UserDefaults = .standard
  var secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  var applicationSupport: URL? = nil

  var profile: String? {
    guard let data = GalaxySSIEncryptedStateStore.load(defaults: defaults, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data),
          !state.profile.identityFingerprint.isBlank else { return nil }
    return state.profile.identityFingerprint
  }

  func allows(_ job: AgentIOSOriginalPageArchiveStore.Job) -> Bool {
    guard let encrypted = defaults.data(forKey: GalaxySSIEncryptedStateStore.stateKey),
          let plaintext = GalaxySSIEncryptedStateStore.load(defaults: defaults, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: plaintext),
          !job.profile.isBlank, state.profile.identityFingerprint == job.profile,
          !state.agentSafetySettings.executionPaused, state.agentSafetySettings.connectorCallsAllowed,
          state.agentSafetySettings.taskExecutionMode != .planOnly,
          let identifier = defaults.string(forKey: "galaxyssi_agent_conversation_database_id_v1"),
          UUID(uuidString: identifier) != nil else { return false }
    let root = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    guard let directory = root?.appendingPathComponent("GalaxySSI/History", isDirectory: true) else { return false }
    let sessions = directory.appendingPathComponent("agent-conversations-\(identifier).sqlite")
    let history = directory.appendingPathComponent("chat-history-\(identifier).sqlite")
    let sessionCipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: "agent.conversations.row.aes256.v1")
    guard let row = rows(sessions, sql: "SELECT conversation_id, encrypted_payload FROM agent_conversations WHERE conversation_id = ? LIMIT 1", values: [job.conversation])?.first,
          row.0 == job.conversation,
          let data = try? sessionCipher.decrypt(row.1, expectedPurpose: "agent-conversation:\(job.conversation)"),
          let conversation = try? JSONDecoder().decode(AgentConversation.self, from: data),
          conversation.id == job.conversation, conversation.status == .active,
          !conversation.privateMode, !conversation.trackingPaused, conversation.mergedIntoConversationId.isBlank else { return false }
    let chatCipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: "chat.history.row.aes256.v1")
    guard let index = try? chatCipher.chatTurnTimingIndex(conversationId: job.conversation, turnId: job.turn),
          let messages = rows(history, sql: """
            SELECT message_id, encrypted_payload FROM chat_messages
            WHERE conversation_id = ? AND agent_turn_key = ? AND is_mine = 1 AND is_system = 0 LIMIT 2
            """, values: [job.conversation, index]),
          messages.contains(where: { row in
            guard let data = try? chatCipher.decrypt(row.1, expectedPurpose: "chat-message:\(row.0)"),
                  let message = try? JSONDecoder().decode(ChatMessage.self, from: data) else { return false }
            return UUID(uuidString: row.0) == message.id && message.conversationId == job.conversation &&
              message.isMine && !message.isSystem && AgentReplyWaitingIndicatorPolicy.turnKey(for: message) == job.turn
          }), defaults.string(forKey: "galaxyssi_agent_conversation_database_id_v1") == identifier,
          defaults.data(forKey: GalaxySSIEncryptedStateStore.stateKey) == encrypted else { return false }
    return true
  }

  private func rows(_ file: URL, sql: String, values: [String]) -> [(String, Data)]? {
    guard let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          attributes.isRegularFile == true, attributes.isSymbolicLink != true else { return nil }
    var database: OpaquePointer?
    guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let database { sqlite3_close_v2(database) }
      return nil
    }
    defer { sqlite3_close_v2(database) }
    sqlite3_busy_timeout(database, 1_000)
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() {
      guard sqlite3_bind_text(statement, Int32(offset + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { return nil }
    }
    var result: [(String, Data)] = []
    while true {
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return result }
      guard step == SQLITE_ROW, result.count < 2, let id = sqlite3_column_text(statement, 0),
            let bytes = sqlite3_column_blob(statement, 1) else { return nil }
      let count = Int(sqlite3_column_bytes(statement, 1))
      guard count > 0, count <= 4 * 1_024 * 1_024 else { return nil }
      result.append((String(cString: id), Data(bytes: bytes, count: count)))
    }
  }
}
