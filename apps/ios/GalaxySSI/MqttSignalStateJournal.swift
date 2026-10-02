import Foundation

// One local Signal identity per database. The owner must quiesce the legacy engine before migration.
final class MqttSignalStateJournal {
  static let maximumBytes = 32 * 1024 * 1024
  private let database: MqttChunkDatabase
  let inbox: MqttBusinessInbox
  let outbox: MqttBusinessOutbox

  init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
       inboxLimits: MqttBusinessInbox.Limits = .init(), outboxLimits: MqttBusinessOutbox.Limits = .init()) throws {
    database = try MqttChunkDatabase(fileURL: fileURL, secrets: secrets)
    inbox = try MqttBusinessInbox(database: database, limits: inboxLimits)
    outbox = try MqttBusinessOutbox(database: database, limits: outboxLimits)
  }

  func load() throws -> Data? { try database.transaction { try read() } }

  // Compare the exact last committed snapshot before invoking libsignal. A stale engine must reopen,
  // not overwrite another engine's ratchet. Neither the result nor its receipt escapes before COMMIT.
  func commit<T>(expected: Data?, _ operation: (MqttChunkDatabase.Transaction) throws -> (T, Data)) throws -> (T, Data) {
    try database.withTransaction { transaction in
      guard try read() == expected else { throw MqttChunkStorageError.corruptState }
      let (result, state) = try operation(transaction)
      guard !state.isEmpty, state.count <= Self.maximumBytes else { throw MqttChunkStorageError.capacityExceeded }
      if state != expected {
        let encrypted = try database.seal(state, purpose: "mqtt-signal-state-v1")
        try database.run("INSERT INTO mqtt_signal_state(id,encrypted_state) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET encrypted_state=excluded.encrypted_state",
          [.blob(encrypted)])
      }
      return (result, state)
    }
  }

  private func read() throws -> Data? {
    let saved = try database.query("SELECT encrypted_state FROM mqtt_signal_state WHERE id=1", maximumRows: 1) {
      let state = try database.open($0.data(0, maximum: Self.maximumBytes + 8192), purpose: "mqtt-signal-state-v1")
      guard !state.isEmpty, state.count <= Self.maximumBytes else { throw MqttChunkStorageError.corruptState }
      return state
    }.first
    if saved == nil {
      let businessRecords = try database.query("SELECT (SELECT COUNT(*) FROM mqtt_business_inbox) + (SELECT COUNT(*) FROM mqtt_business_ciphertexts) + (SELECT COUNT(*) FROM mqtt_business_outbox)",
        maximumRows: 1) { try $0.number(0) }.first
      guard businessRecords == 0 else { throw MqttChunkStorageError.corruptState }
    }
    return saved
  }
}
