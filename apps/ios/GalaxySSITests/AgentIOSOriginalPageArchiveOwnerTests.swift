import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentIOSOriginalPageArchiveOwnerTests: XCTestCase {
  private final class Secrets: GalaxySSISecretStore {
    var values: [String: String] = [:]
    var writes = 0
    func setString(_ value: String, account: String) throws { values[account] = value; writes += 1 }
    func string(account: String) -> String? { values[account] }
    func delete(account: String) { values.removeValue(forKey: account) }
  }
  private final class Fixture {
    let suite = "synthetic-archive-owner-" + UUID().uuidString
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let secrets = Secrets()
    let identifier = UUID().uuidString.lowercased()
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    var owner: AgentIOSOriginalPageArchiveOwner { .init(defaults: defaults, secrets: secrets, applicationSupport: root) }
    var sessions: AgentConversationDatabase!
    var history: GalaxySSIChatHistoryDatabase!
    var conversation = AgentConversation(id: "session", title: "Synthetic", createdAt: 1, updatedAt: 1)
    var job: AgentIOSOriginalPageArchiveStore.Job {
      .init(id: String(repeating: "a", count: 64), profile: "profile-a", conversation: "session", turn: "turn", url: "https://example.com", name: "page", language: "en", source: Data("<p>Source</p>".utf8))
    }
    var historyURL: URL { root.appendingPathComponent("GalaxySSI/History/chat-history-\(identifier).sqlite") }
    init() throws {
      defaults.set(identifier, forKey: "galaxyssi_agent_conversation_database_id_v1")
      try state()
      sessions = .init(fileURL: root.appendingPathComponent("GalaxySSI/History/agent-conversations-\(identifier).sqlite"), secrets: secrets)
      history = .init(fileURL: historyURL, secrets: secrets)
      XCTAssertTrue(sessions.upsert(conversation))
      XCTAssertTrue(history.upsert(ChatMessage(contactId: "hermes", content: "Read public page", isMine: true, conversationId: "session", turnId: "turn")))
    }
    func state(profile: String = "profile-a", safety: AgentSafetySettings = .default) throws {
      let policy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(safety))
      let data = try JSONSerialization.data(withJSONObject: ["profile": ["identityFingerprint": profile], "agentSafetySettings": policy])
      XCTAssertTrue(GalaxySSIEncryptedStateStore.write(data, defaults: defaults, secrets: secrets))
    }
    deinit {
      sessions = nil; history = nil
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testColdOwnerFailsClosedWithoutCreatingStateIdentityOrHistory() {
    let suite = "synthetic-empty-archive-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!, secrets = Secrets()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let owner = AgentIOSOriginalPageArchiveOwner(defaults: defaults, secrets: secrets, applicationSupport: root)
    XCTAssertNil(owner.profile)
    XCTAssertNil(defaults.string(forKey: "galaxyssi_agent_conversation_database_id_v1"))
    XCTAssertNil(defaults.data(forKey: GalaxySSIEncryptedStateStore.stateKey))
    XCTAssertEqual(secrets.writes, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }

  func testColdOwnerRechecksProfilePrivacyPauseAndOriginalTurnWithoutWrites() throws {
    let fixture = try Fixture()
    let originalState = fixture.defaults.data(forKey: GalaxySSIEncryptedStateStore.stateKey)
    let writes = fixture.secrets.writes
    XCTAssertEqual(fixture.owner.profile, "profile-a")
    XCTAssertTrue(fixture.owner.allows(fixture.job))
    XCTAssertEqual(fixture.defaults.data(forKey: GalaxySSIEncryptedStateStore.stateKey), originalState)
    XCTAssertEqual(fixture.secrets.writes, writes)
    var foreign = fixture.job; foreign.turn = "another-turn"
    XCTAssertFalse(fixture.owner.allows(foreign))
    fixture.conversation.privateMode = true
    XCTAssertTrue(fixture.sessions.upsert(fixture.conversation))
    XCTAssertFalse(fixture.owner.allows(fixture.job))
    fixture.conversation.privateMode = false; fixture.conversation.trackingPaused = true
    XCTAssertTrue(fixture.sessions.upsert(fixture.conversation))
    XCTAssertFalse(fixture.owner.allows(fixture.job))
    fixture.conversation.trackingPaused = false
    XCTAssertTrue(fixture.sessions.upsert(fixture.conversation))
    try fixture.state(safety: .init(executionPaused: true))
    XCTAssertFalse(fixture.owner.allows(fixture.job))
    try fixture.state(profile: "profile-b")
    XCTAssertFalse(fixture.owner.allows(fixture.job))
  }

  func testColdOwnerDoesNotHydrateMissingIndexOrCreateMissingDatabase() throws {
    let fixture = try Fixture()
    XCTAssertTrue(fixture.owner.allows(fixture.job))
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(fixture.historyURL.path, &database, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_exec(database, "UPDATE chat_messages SET agent_turn_key = NULL", nil, nil, nil), SQLITE_OK)
    sqlite3_close_v2(database)
    XCTAssertFalse(fixture.owner.allows(fixture.job))
    XCTAssertFalse(fixture.owner.allows(fixture.job))
    let missing = UUID().uuidString.lowercased()
    fixture.defaults.set(missing, forKey: "galaxyssi_agent_conversation_database_id_v1")
    XCTAssertFalse(fixture.owner.allows(fixture.job))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("GalaxySSI/History/agent-conversations-\(missing).sqlite").path))
  }
}
