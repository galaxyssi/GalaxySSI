import CryptoKit
import Foundation
import SQLite3

final class AgentTeamHistoryDatabase {
  enum Failure: Error { case unavailable, corrupt, stale }
  private let namespace: String
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private var database: OpaquePointer?

  init(fileURL: URL, storageKey: String, secrets: GalaxySSISecretStore) throws {
    namespace = Self.digest(storageKey)
    cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: "agent.team.history.\(namespace).aes256.v1")
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    var ready = false
    defer { if !ready, let database { sqlite3_close_v2(database); self.database = nil } }
    guard sqlite3_open_v2(fileURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      throw Failure.unavailable
    }
    sqlite3_busy_timeout(database, 5_000)
    try execute("PRAGMA journal_mode = WAL")
    try execute("PRAGMA synchronous = FULL")
    try execute("PRAGMA foreign_keys = ON")
    try execute("PRAGMA fullfsync = ON")
    try execute("""
      CREATE TABLE IF NOT EXISTS team_history (
        namespace TEXT NOT NULL, run_key TEXT NOT NULL, updated_at INTEGER NOT NULL,
        finished INTEGER NOT NULL, conversation_key TEXT NOT NULL, encrypted_payload BLOB NOT NULL, PRIMARY KEY(namespace,run_key))
      """)
    try execute("CREATE INDEX IF NOT EXISTS team_history_retention ON team_history(namespace,finished,updated_at,run_key)")
    try execute("CREATE INDEX IF NOT EXISTS team_history_recent ON team_history(namespace,updated_at,run_key)")
    try execute("CREATE INDEX IF NOT EXISTS team_history_pending ON team_history(namespace,conversation_key,finished,updated_at)")
    try execute("CREATE INDEX IF NOT EXISTS team_history_recovery ON team_history(namespace,finished,run_key)")
    try execute("""
      CREATE TABLE IF NOT EXISTS collaboration_goal_checkpoints (
        namespace TEXT NOT NULL, run_key TEXT NOT NULL, revision INTEGER NOT NULL,
        encrypted_payload BLOB NOT NULL, PRIMARY KEY(namespace,run_key,revision),
        FOREIGN KEY(namespace,run_key) REFERENCES team_history(namespace,run_key) ON DELETE CASCADE)
      """)
    try execute("CREATE TABLE IF NOT EXISTS team_history_migrations(namespace TEXT PRIMARY KEY)")
    try execute("""
      CREATE TABLE IF NOT EXISTS collaboration_cloud_evidence (
        namespace TEXT NOT NULL, group_key TEXT NOT NULL, evidence_id TEXT NOT NULL,
        encrypted_payload BLOB NOT NULL, PRIMARY KEY(namespace,group_key,evidence_id))
      """)
    try execute("""
      CREATE TABLE IF NOT EXISTS collaboration_cloud_problems (
        namespace TEXT NOT NULL, group_key TEXT NOT NULL, evidence_id TEXT NOT NULL,
        turn_key TEXT NOT NULL, scope_key TEXT NOT NULL,
        PRIMARY KEY(namespace,group_key,evidence_id),
        FOREIGN KEY(namespace,group_key,evidence_id)
          REFERENCES collaboration_cloud_evidence(namespace,group_key,evidence_id) ON DELETE CASCADE)
      """)
    try execute("""
      CREATE TABLE IF NOT EXISTS collaboration_research_records (
        namespace TEXT NOT NULL, group_key TEXT NOT NULL, record_key TEXT NOT NULL,
        revision INTEGER NOT NULL, encrypted_payload BLOB NOT NULL,
        PRIMARY KEY(namespace,group_key,record_key,revision))
      """)
    try execute("""
      CREATE TABLE IF NOT EXISTS team_reply_owners (
        namespace TEXT NOT NULL, binding_key TEXT NOT NULL, run_key TEXT NOT NULL,
        member_key TEXT NOT NULL, encrypted_payload BLOB NOT NULL,
        PRIMARY KEY(namespace,binding_key,run_key,member_key))
      """)
    try execute("CREATE TABLE IF NOT EXISTS team_reply_owner_backfill(namespace TEXT NOT NULL,conversation_key TEXT NOT NULL,PRIMARY KEY(namespace,conversation_key))")
    ready = true
  }

  deinit { if let database { sqlite3_close_v2(database) } }

  func transaction<T>(_ operation: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute("ROLLBACK") } }
    let result = try operation()
    try execute("COMMIT")
    committed = true
    return result
  }

  func initialized() throws -> Bool {
    let statement = try prepare("SELECT namespace FROM team_history_migrations WHERE namespace=?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    switch sqlite3_step(statement) {
    case SQLITE_ROW: return true
    case SQLITE_DONE: return false
    default: throw Failure.unavailable
    }
  }

  func prepareMailbox() throws {
    try execute("""
      CREATE TABLE IF NOT EXISTS team_mailbox (
        namespace TEXT NOT NULL, message_key TEXT NOT NULL, run_key TEXT NOT NULL, recipient_key TEXT NOT NULL,
        sequence INTEGER NOT NULL, pending INTEGER NOT NULL, payload BLOB NOT NULL,
        PRIMARY KEY(namespace, message_key), UNIQUE(namespace, run_key, sequence)
      )
      """)
    try execute("CREATE INDEX IF NOT EXISTS team_mailbox_pending ON team_mailbox(namespace,run_key,sequence) WHERE pending=1")
    try execute("CREATE INDEX IF NOT EXISTS team_mailbox_pending_recipient ON team_mailbox(namespace,run_key,recipient_key,sequence) WHERE pending=1")
  }

  func mailboxMessage(id: String) throws -> AgentTeamMessageEnvelope? {
    let key = Self.digest(id)
    let statement = try prepare("SELECT message_key,payload FROM team_mailbox WHERE namespace=? AND message_key=?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(key, at: 2, to: statement)
    switch sqlite3_step(statement) {
    case SQLITE_ROW: return try decodeMailboxMessage(statement)
    case SQLITE_DONE: return nil
    default: throw Failure.unavailable
    }
  }

  func nextMailboxSequence(runId: String) throws -> Int64 {
    let statement = try prepare("SELECT sequence FROM team_mailbox WHERE namespace=? AND run_key=? ORDER BY sequence DESC LIMIT 1")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(Self.digest(runId), at: 2, to: statement)
    switch sqlite3_step(statement) {
    case SQLITE_ROW:
      let last = sqlite3_column_int64(statement, 0)
      guard last < Int64.max else { throw Failure.corrupt }
      return last + 1
    case SQLITE_DONE: return 1
    default: throw Failure.unavailable
    }
  }

  func putMailboxMessage(_ message: AgentTeamMessageEnvelope, updating: Bool = false) throws {
    let key = Self.digest(message.messageId)
    let blob = try cipher.encrypt(JSONEncoder().encode(message), purpose: "team-mailbox:\(namespace):\(key)")
    let statement = try prepare("""
      INSERT INTO team_mailbox(namespace,message_key,run_key,recipient_key,sequence,pending,payload)
      VALUES(?,?,?,?,?,?,?)
      """ + (updating ? " ON CONFLICT(namespace,message_key) DO UPDATE SET pending=excluded.pending,payload=excluded.payload" : ""))
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(key, at: 2, to: statement)
    bind(Self.digest(message.supervisorRunId), at: 3, to: statement)
    bind(message.isBroadcast ? "" : Self.digest(message.toInstanceId), at: 4, to: statement)
    sqlite3_bind_int64(statement, 5, message.sequence)
    sqlite3_bind_int(statement, 6, message.state == .pending ? 1 : 0)
    _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 7, $0.baseAddress, Int32($0.count), Self.transient) }
    try finish(statement)
  }

  func mailboxMessages(runId: String, recipient: String, after: Int64, pendingOnly: Bool) throws -> [AgentTeamMessageEnvelope] {
    let statement = try prepare("SELECT message_key,payload FROM team_mailbox WHERE namespace=? AND run_key=? AND sequence>?" +
      (pendingOnly ? " AND pending=1" : "") + (recipient.isEmpty ? "" : " AND recipient_key IN ('',?)") + " ORDER BY sequence")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(Self.digest(runId), at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, after)
    if !recipient.isEmpty { bind(Self.digest(recipient), at: 4, to: statement) }
    var rows: [AgentTeamMessageEnvelope] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW:
        let row = try decodeMailboxMessage(statement)
        guard row.supervisorRunId == runId, row.sequence > after,
              recipient.isEmpty || row.isBroadcast || row.toInstanceId == recipient,
              !pendingOnly || row.state == .pending else { throw Failure.corrupt }
        rows.append(row)
      case SQLITE_DONE: return rows
      default: throw Failure.unavailable
      }
    }
  }

  func recentMailboxMessages(runId: String, conversationId: String, limit: Int) throws -> [AgentTeamMessageEnvelope] {
    let statement = try prepare("SELECT message_key,payload FROM team_mailbox WHERE namespace=? AND run_key=? ORDER BY sequence DESC LIMIT ?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(Self.digest(runId), at: 2, to: statement)
    sqlite3_bind_int(statement, 3, Int32(limit))
    var rows: [AgentTeamMessageEnvelope] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW:
        let row = try decodeMailboxMessage(statement)
        guard row.supervisorRunId == runId, row.conversationId == conversationId else { throw Failure.corrupt }
        rows.append(row)
      case SQLITE_DONE: return Array(rows.reversed())
      default: throw Failure.unavailable
      }
    }
  }

  func clearMailbox(runId: String?) throws {
    let statement = try prepare("DELETE FROM team_mailbox WHERE namespace=?" + (runId == nil ? "" : " AND run_key=?"))
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    if let runId { bind(Self.digest(runId), at: 2, to: statement) }
    try finish(statement)
  }

  private func decodeMailboxMessage(_ statement: OpaquePointer) throws -> AgentTeamMessageEnvelope {
    guard let rawKey = sqlite3_column_text(statement, 0), let blob = sqlite3_column_blob(statement, 1) else { throw Failure.corrupt }
    let key = String(cString: rawKey)
    let bytes = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 1)))
    let row = try JSONDecoder().decode(AgentTeamMessageEnvelope.self,
      from: cipher.decrypt(bytes, purpose: "team-mailbox:\(namespace):\(key)"))
    guard Self.digest(row.messageId) == key else { throw Failure.corrupt }
    return row
  }

  func markInitialized() throws {
    let statement = try prepare("INSERT OR IGNORE INTO team_history_migrations(namespace) VALUES(?)")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    try finish(statement)
  }

  func snapshots(runId: String? = nil, conversation: String? = nil, recoverableOnly: Bool = false, deliverableOnly: Bool = false,
                 limit: Int? = nil, afterRunKey: String? = nil) throws -> [AgentTeamExecutionSnapshot] {
    var sql = "SELECT run_key,updated_at,finished,encrypted_payload,conversation_key FROM team_history WHERE namespace=?"
    var values = [namespace]
    if let runId { sql += " AND run_key=?"; values.append(Self.digest(runId)) }
    if let conversation { sql += " AND conversation_key=?"; values.append(Self.digest(conversation)) }
    if recoverableOnly { sql += " AND finished=0" }
    if deliverableOnly { sql += " AND finished=1" }
    if let afterRunKey { sql += " AND run_key>?"; values.append(afterRunKey) }
    sql += afterRunKey == nil ? " ORDER BY updated_at DESC,run_key DESC" : " ORDER BY run_key"
    if limit != nil { sql += " LIMIT ?" }
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() { bind(value, at: Int32(offset + 1), to: statement) }
    if let limit { sqlite3_bind_int64(statement, Int32(values.count + 1), Int64(max(0, limit))) }
    var result: [AgentTeamExecutionSnapshot] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return result }
      guard status == SQLITE_ROW else { throw Failure.unavailable }
      guard let key = sqlite3_column_text(statement, 0), let blob = sqlite3_column_blob(statement, 3),
            let conversation = sqlite3_column_text(statement, 4) else { throw Failure.corrupt }
      let runKey = String(cString: key)
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 3)))
      let snapshot = try JSONDecoder().decode(AgentTeamExecutionSnapshot.self, from: cipher.decrypt(data, purpose: purpose(runKey)))
      guard Self.digest(snapshot.supervisorRunId) == runKey,
            snapshot.updatedAtMillis == sqlite3_column_int64(statement, 1),
            Self.digest(snapshot.conversationId) == String(cString: conversation),
            (snapshot.state.deliverable ? 1 : 0) == sqlite3_column_int(statement, 2) else { throw Failure.corrupt }
      result.append(snapshot)
    }
  }

  func recoveryPage(after: String, limit: Int) throws -> (teams: [AgentTeamExecutionSnapshot], next: String?) {
    let size = min(16, max(1, limit))
    let rows = try snapshots(recoverableOnly: true, limit: size + 1, afterRunKey: after)
    let teams = Array(rows.prefix(size))
    return (teams, rows.count > size ? teams.last.map { Self.digest($0.supervisorRunId) } : nil)
  }

  func publicationRecoveryPage(after: String) throws -> (teams: [AgentTeamExecutionSnapshot], next: String?) {
    let size = 8
    let rows = try snapshots(limit: size + 1, afterRunKey: after)
    let teams = Array(rows.prefix(size))
    return (teams, rows.count > size ? teams.last.map { Self.digest($0.supervisorRunId) } : nil)
  }

  func put(_ snapshot: AgentTeamExecutionSnapshot) throws {
    let key = Self.digest(snapshot.supervisorRunId)
    let encrypted = try cipher.encrypt(JSONEncoder().encode(snapshot), purpose: purpose(key))
    let statement = try prepare("""
      INSERT INTO team_history(namespace,run_key,updated_at,finished,conversation_key,encrypted_payload) VALUES(?,?,?,?,?,?)
      ON CONFLICT(namespace,run_key) DO UPDATE SET updated_at=excluded.updated_at,
        finished=excluded.finished,conversation_key=excluded.conversation_key,encrypted_payload=excluded.encrypted_payload
      """)
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(key, at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, snapshot.updatedAtMillis)
    sqlite3_bind_int(statement, 4, snapshot.state.deliverable ? 1 : 0)
    bind(Self.digest(snapshot.conversationId), at: 5, to: statement)
    _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 6, $0.baseAddress, Int32($0.count), Self.transient) }
    try finish(statement)
    try recordReplyOwners(snapshot)
  }

  func goalCheckpoints(runId: String, revision: Int64? = nil, newestOnly: Bool = false) throws
    -> [AgentCollaborationGoalCheckpoint] {
    let key = Self.digest(runId)
    let statement = try prepare("SELECT revision,encrypted_payload FROM collaboration_goal_checkpoints " +
      "WHERE namespace=? AND run_key=?" + (revision == nil ? "" : " AND revision=?") +
      " ORDER BY revision DESC" + (newestOnly ? " LIMIT 1" : ""))
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(key, at: 2, to: statement)
    if let revision { sqlite3_bind_int64(statement, 3, revision) }
    var result: [AgentCollaborationGoalCheckpoint] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return result }
      guard status == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 1) else { throw Failure.corrupt }
      let rowRevision = sqlite3_column_int64(statement, 0)
      let payload = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 1)))
      let checkpoint = try JSONDecoder().decode(AgentCollaborationGoalCheckpoint.self,
        from: cipher.decrypt(payload, purpose: goalPurpose(key, revision: rowRevision)))
      guard checkpoint.runId == runId, checkpoint.revision == rowRevision else { throw Failure.corrupt }
      result.append(checkpoint)
    }
  }

  func insertGoalCheckpoint(_ checkpoint: AgentCollaborationGoalCheckpoint) throws {
    let key = Self.digest(checkpoint.runId)
    let data = try JSONEncoder().encode(checkpoint)
    guard data.count <= 256_000 else { throw Failure.corrupt }
    let encrypted = try cipher.encrypt(data, purpose: goalPurpose(key, revision: checkpoint.revision))
    let statement = try prepare("INSERT INTO collaboration_goal_checkpoints VALUES(?,?,?,?)")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(key, at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, checkpoint.revision)
    _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), Self.transient) }
    try finish(statement)
  }

  private func goalPurpose(_ key: String, revision: Int64) -> String {
    "collaboration-goal:\(namespace):\(key):\(revision)"
  }

  func remove(runId: String? = nil, preserveOwners: Bool = false) throws {
    let statement = try prepare("DELETE FROM team_history WHERE namespace=?" + (runId == nil ? "" : " AND run_key=?"))
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    if let runId { bind(Self.digest(runId), at: 2, to: statement) }
    try finish(statement)
    if runId == nil {
      try removeCloudEvidence(conversationId: nil)
      try removeResearchRecords(conversationId: nil)
      for table in preserveOwners ? [] : ["team_reply_owners", "team_reply_owner_backfill"] {
        let clear = try prepare("DELETE FROM \(table) WHERE namespace=?")
        defer { sqlite3_finalize(clear) }
        bind(namespace, at: 1, to: clear)
        try finish(clear)
      }
      try markInitialized()
    }
  }

  func cloudEvidence(id: String, conversationId: String) throws -> AgentCollaborationCloudToolEvidence? {
    let group = Self.digest(conversationId)
    let statement = try prepare("SELECT encrypted_payload FROM collaboration_cloud_evidence WHERE namespace=? AND group_key=? AND evidence_id=?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(group, at: 2, to: statement)
    bind(id, at: 3, to: statement)
    let status = sqlite3_step(statement)
    if status == SQLITE_DONE { return nil }
    guard status == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) else { throw Failure.corrupt }
    let bytes = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
    return try JSONDecoder().decode(AgentCollaborationCloudToolEvidence.self,
      from: cipher.decrypt(bytes, purpose: "cloud-evidence:\(namespace):\(group):\(id)"))
  }

  func insertCloudEvidence(_ evidence: AgentCollaborationCloudToolEvidence, id: String) throws {
    let group = Self.digest(evidence.scope.conversationId)
    let bytes = try JSONEncoder().encode(evidence)
    guard bytes.count <= 2_000_000 else { throw Failure.corrupt }
    let payload = try cipher.encrypt(bytes, purpose: "cloud-evidence:\(namespace):\(group):\(id)")
    let statement = try prepare("INSERT INTO collaboration_cloud_evidence VALUES(?,?,?,?)")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(group, at: 2, to: statement)
    bind(id, at: 3, to: statement)
    _ = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), Self.transient) }
    try finish(statement)
  }

  func removeCloudEvidence(conversationId: String?) throws {
    let statement = try prepare("DELETE FROM collaboration_cloud_evidence WHERE namespace=?" +
      (conversationId == nil ? "" : " AND group_key=?"))
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    if let conversationId { bind(Self.digest(conversationId), at: 2, to: statement) }
    try finish(statement)
  }

  private static func cloudProblemScopeKey(_ scope: AgentCollaborationToolEvidenceScope) -> String {
    AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "group": .string(scope.conversationId), "turn": .string(scope.turnId),
      "member": .string(scope.memberId), "source": .string(scope.sourceId)
    ])
  }

  func indexCloudProblem(id: String, scope: AgentCollaborationToolEvidenceScope) throws {
    let statement = try prepare("INSERT OR IGNORE INTO collaboration_cloud_problems VALUES(?,?,?,?,?)")
    defer { sqlite3_finalize(statement) }
    for (index, value) in [namespace, Self.digest(scope.conversationId), id,
                           Self.digest(scope.turnId), Self.cloudProblemScopeKey(scope)].enumerated() {
      bind(value, at: Int32(index + 1), to: statement)
    }
    try finish(statement)
  }

  func cloudProblemIds(scope: AgentCollaborationToolEvidenceScope, after: String, limit: Int) throws -> [String] {
    let statement = try prepare("""
      SELECT evidence_id FROM collaboration_cloud_problems
      WHERE namespace=? AND group_key=? AND evidence_id>? AND (turn_key<>? OR scope_key=?)
      ORDER BY evidence_id LIMIT ?
      """)
    defer { sqlite3_finalize(statement) }
    for (index, value) in [namespace, Self.digest(scope.conversationId), after,
                           Self.digest(scope.turnId), Self.cloudProblemScopeKey(scope)].enumerated() {
      bind(value, at: Int32(index + 1), to: statement)
    }
    sqlite3_bind_int64(statement, 6, Int64(limit))
    var result: [String] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return result }
      guard status == SQLITE_ROW, let id = sqlite3_column_text(statement, 0) else { throw Failure.corrupt }
      result.append(String(cString: id))
    }
  }

  func researchObjectHeads(conversationId: String, after: String, limit: Int)
    throws -> [AgentCollaborationCapabilityPage.Row] {
    let statement = try prepare("""
      SELECT record_key, MAX(revision) FROM collaboration_research_records
      WHERE namespace=? AND group_key=? AND record_key>? AND record_key<'object;'
      GROUP BY record_key ORDER BY record_key LIMIT ?
      """)
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(Self.digest(conversationId), at: 2, to: statement)
    bind("object:" + after, at: 3, to: statement)
    sqlite3_bind_int64(statement, 4, Int64(limit))
    var rows: [AgentCollaborationCapabilityPage.Row] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW, let key = sqlite3_column_text(statement, 0) else { throw Failure.corrupt }
      let recordKey = String(cString: key)
      let revision = sqlite3_column_int64(statement, 1)
      guard recordKey.hasPrefix("object:"), revision > 0 else { throw Failure.corrupt }
      rows.append(.init(objectID: String(recordKey.dropFirst("object:".count)), revision: revision))
    }
  }

  func milestoneKeys(conversationId: String, prefix: String, after: String) throws -> [String] {
    guard prefix.hasSuffix(":") else { throw Failure.corrupt }
    let statement = try prepare("""
      SELECT record_key FROM collaboration_research_records
      WHERE namespace=? AND group_key=? AND record_key>? AND record_key<? AND revision=0
      ORDER BY record_key LIMIT 33
      """)
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(Self.digest(conversationId), at: 2, to: statement)
    bind(after.isEmpty ? prefix : after, at: 3, to: statement)
    bind(String(prefix.dropLast()) + ";", at: 4, to: statement)
    var keys: [String] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return keys }
      guard status == SQLITE_ROW, let key = sqlite3_column_text(statement, 0) else { throw Failure.corrupt }
      keys.append(String(cString: key))
    }
  }

  func modelCallAdmissionKeys(conversationId: String, after: String, limit: Int) throws -> [String] {
    let statement = try prepare("""
      SELECT record_key FROM collaboration_research_records
      WHERE namespace=? AND group_key=? AND record_key>? AND record_key<'model-call;' AND revision=0
      ORDER BY record_key LIMIT ?
      """)
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(Self.digest(conversationId), at: 2, to: statement)
    bind("model-call:" + after, at: 3, to: statement)
    sqlite3_bind_int64(statement, 4, Int64(limit))
    var keys: [String] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return keys }
      guard status == SQLITE_ROW, let key = sqlite3_column_text(statement, 0) else { throw Failure.corrupt }
      keys.append(String(cString: key))
    }
  }

  func researchRecord<T: Decodable>(_ type: T.Type, conversationId: String, key: String,
                                    revision: Int64? = nil) throws -> T? {
    let group = Self.digest(conversationId)
    let statement = try prepare("SELECT revision,encrypted_payload FROM collaboration_research_records " +
      "WHERE namespace=? AND group_key=? AND record_key=?" + (revision == nil ? "" : " AND revision=?") +
      " ORDER BY revision DESC LIMIT 1")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(group, at: 2, to: statement)
    bind(key, at: 3, to: statement)
    if let revision { sqlite3_bind_int64(statement, 4, revision) }
    let result = sqlite3_step(statement)
    if result == SQLITE_DONE { return nil }
    guard result == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 1) else { throw Failure.corrupt }
    let rowRevision = sqlite3_column_int64(statement, 0)
    let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 1)))
    return try JSONDecoder().decode(type, from: cipher.decrypt(data,
      purpose: researchPurpose(group: group, key: key, revision: rowRevision)))
  }

  func insertResearchRecord<T: Encodable>(_ record: T, conversationId: String, key: String,
                                           revision: Int64, replaceCoverage: Bool = false) throws {
    let group = Self.digest(conversationId)
    let data = try JSONEncoder().encode(record)
    let limit = (record as? AgentCollaborationResearchRevision)?.storageBytesLimit
      ?? AgentCollaborationResearchRevision.standardStorageBytes
    guard data.count <= limit else { throw Failure.corrupt }
    let payload = try cipher.encrypt(data, purpose: researchPurpose(group: group, key: key, revision: revision))
    guard !replaceCoverage || (key.hasPrefix("cloud-read-coverage:") && revision == 0) else { throw Failure.corrupt }
    let insert = replaceCoverage ? "INSERT OR REPLACE" : "INSERT"
    let statement = try prepare(insert + " INTO collaboration_research_records VALUES(?,?,?,?,?)")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(group, at: 2, to: statement)
    bind(key, at: 3, to: statement)
    sqlite3_bind_int64(statement, 4, revision)
    _ = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32($0.count), Self.transient) }
    try finish(statement)
  }

  func removeResearchRecords(conversationId: String?) throws {
    let statement = try prepare("DELETE FROM collaboration_research_records WHERE namespace=?" +
      (conversationId == nil ? "" : " AND group_key=?"))
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    if let conversationId { bind(Self.digest(conversationId), at: 2, to: statement) }
    try finish(statement)
  }

  func desktopEvidenceJobs(after: String, limit: Int) throws -> [AgentDesktopToolEvidenceWire.ImportJob] {
    let statement = try prepare("""
      SELECT group_key,record_key,encrypted_payload FROM collaboration_research_records
      WHERE namespace=? AND record_key LIKE 'desktop-evidence-job:%' AND record_key>? AND revision=0
      ORDER BY record_key LIMIT ?
      """)
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(after, at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, Int64(limit))
    var jobs: [AgentDesktopToolEvidenceWire.ImportJob] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return jobs }
      guard status == SQLITE_ROW, let group = sqlite3_column_text(statement, 0),
            let key = sqlite3_column_text(statement, 1),
            let blob = sqlite3_column_blob(statement, 2) else { throw Failure.corrupt }
      let groupId = String(cString: group)
      let recordKey = String(cString: key)
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
      let job = try JSONDecoder().decode(AgentDesktopToolEvidenceWire.ImportJob.self,
        from: cipher.decrypt(data, purpose: researchPurpose(group: groupId, key: recordKey, revision: 0)))
      guard job.key == recordKey, Self.digest(job.binding.identity.conversationId) == groupId else {
        throw Failure.corrupt
      }
      jobs.append(job)
    }
  }

  func removeDesktopEvidenceJob(_ job: AgentDesktopToolEvidenceWire.ImportJob) throws {
    try removeResearchRecord(conversationId: job.binding.identity.conversationId, key: job.key)
  }

  func removeResearchRecord(conversationId: String, key: String) throws {
    let statement = try prepare("DELETE FROM collaboration_research_records WHERE namespace=? AND group_key=? AND record_key=?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(Self.digest(conversationId), at: 2, to: statement)
    bind(key, at: 3, to: statement)
    try finish(statement)
  }

  private func researchPurpose(group: String, key: String, revision: Int64) -> String {
    "collaboration-research:\(namespace):\(group):\(key):\(revision)"
  }

  func replyOwner(source: String, conversation: String, turn: String, contact: String) throws -> AgentTeamReplyOwner? {
    if let known = try knownReplyOwner(source: source, conversation: conversation, turn: turn, contact: contact) { return known }
    let marker = try prepare("SELECT 1 FROM team_reply_owner_backfill WHERE namespace=? AND conversation_key=?")
    defer { sqlite3_finalize(marker) }
    bind(namespace, at: 1, to: marker)
    bind(Self.digest(conversation), at: 2, to: marker)
    let status = sqlite3_step(marker)
    if status == SQLITE_DONE {
      for snapshot in try snapshots(conversation: conversation) { try recordReplyOwners(snapshot) }
      let insert = try prepare("INSERT INTO team_reply_owner_backfill(namespace,conversation_key) VALUES(?,?)")
      defer { sqlite3_finalize(insert) }
      bind(namespace, at: 1, to: insert)
      bind(Self.digest(conversation), at: 2, to: insert)
      try finish(insert)
    } else if status != SQLITE_ROW { throw Failure.unavailable }
    return try knownReplyOwner(source: source, conversation: conversation, turn: turn, contact: contact)
  }

  private func knownReplyOwner(source: String, conversation: String, turn: String, contact: String) throws -> AgentTeamReplyOwner? {
    let key = try replyKey(source: source, conversation: conversation, turn: turn, contact: contact)
    let statement = try prepare("SELECT run_key,member_key,encrypted_payload FROM team_reply_owners WHERE namespace=? AND binding_key=? LIMIT 2")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(key, at: 2, to: statement)
    let row = sqlite3_step(statement)
    if row == SQLITE_DONE { return nil }
    guard row == SQLITE_ROW, let run = sqlite3_column_text(statement, 0),
          let member = sqlite3_column_text(statement, 1), let blob = sqlite3_column_blob(statement, 2) else { throw Failure.corrupt }
    let runKey = String(cString: run)
    let memberKey = String(cString: member)
    let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
    let owner = try JSONDecoder().decode(AgentTeamReplyOwner.self,
      from: cipher.decrypt(data, purpose: ownerPurpose(key, runKey, memberKey)))
    guard Self.digest(owner.supervisorRunId) == runKey, Self.digest(owner.memberId) == memberKey,
          owner.sourceMessageId == source, owner.conversationId == conversation,
          owner.turnId == turn, owner.contactId == contact, sqlite3_step(statement) == SQLITE_DONE else { throw Failure.corrupt }
    return owner
  }

  private func recordReplyOwners(_ snapshot: AgentTeamExecutionSnapshot) throws {
    guard !snapshot.conversationId.isBlank, !snapshot.taskId.isBlank else { return }
    for member in snapshot.members where !member.sourceMessageId.isBlank && !member.agentId.isBlank {
      let owner = AgentTeamReplyOwner(supervisorRunId: snapshot.supervisorRunId, memberId: member.memberId,
        conversationId: snapshot.conversationId, turnId: snapshot.taskId, sourceMessageId: member.sourceMessageId,
        contactId: member.agentId, deliveryMode: member.deliveryMode)
      let key = try replyKey(source: owner.sourceMessageId, conversation: owner.conversationId, turn: owner.turnId, contact: owner.contactId)
      let run = Self.digest(owner.supervisorRunId)
      let memberKey = Self.digest(owner.memberId)
      let existing = try prepare("SELECT encrypted_payload FROM team_reply_owners WHERE namespace=? AND binding_key=? AND run_key=? AND member_key=?")
      defer { sqlite3_finalize(existing) }
      for (index, value) in [namespace, key, run, memberKey].enumerated() { bind(value, at: Int32(index + 1), to: existing) }
      let status = sqlite3_step(existing)
      if status == SQLITE_ROW {
        guard let blob = sqlite3_column_blob(existing, 0) else { throw Failure.corrupt }
        let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(existing, 0)))
        let prior = try JSONDecoder().decode(AgentTeamReplyOwner.self, from: cipher.decrypt(data, purpose: ownerPurpose(key, run, memberKey)))
        var identity = prior
        identity.observedGeneration = nil
        identity.observedSequence = nil
        identity.closedRecallGeneration = nil
        identity.recallEventGeneration = nil
        guard identity == owner else { throw Failure.stale }
        continue
      }
      guard status == SQLITE_DONE else { throw Failure.unavailable }
      let encrypted = try cipher.encrypt(JSONEncoder().encode(owner), purpose: ownerPurpose(key, run, memberKey))
      let insert = try prepare("INSERT INTO team_reply_owners(namespace,binding_key,run_key,member_key,encrypted_payload) VALUES(?,?,?,?,?)")
      defer { sqlite3_finalize(insert) }
      for (index, value) in [namespace, key, run, memberKey].enumerated() { bind(value, at: Int32(index + 1), to: insert) }
      _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(insert, 5, $0.baseAddress, Int32($0.count), Self.transient) }
      try finish(insert)
    }
  }

  private func replyKey(source: String, conversation: String, turn: String, contact: String) throws -> String {
    let data = try JSONEncoder().encode([conversation, turn, source, contact])
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  func updateReplyOwner(_ owner: AgentTeamReplyOwner) throws {
    let key = try replyKey(source: owner.sourceMessageId, conversation: owner.conversationId,
      turn: owner.turnId, contact: owner.contactId)
    let run = Self.digest(owner.supervisorRunId)
    let member = Self.digest(owner.memberId)
    let encrypted = try cipher.encrypt(JSONEncoder().encode(owner), purpose: ownerPurpose(key, run, member))
    let statement = try prepare("UPDATE team_reply_owners SET encrypted_payload=? WHERE namespace=? AND binding_key=? AND run_key=? AND member_key=?")
    defer { sqlite3_finalize(statement) }
    _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), Self.transient) }
    for (index, value) in [namespace, key, run, member].enumerated() { bind(value, at: Int32(index + 2), to: statement) }
    try finish(statement)
    guard sqlite3_changes(database) == 1 else { throw Failure.stale }
  }
  private func ownerPurpose(_ key: String, _ run: String, _ member: String) -> String {
    "team-reply-owner:\(namespace):\(key):\(run):\(member)"
  }

  func pruneFinished() throws {
    let statement = try prepare("""
      DELETE FROM team_history WHERE namespace=? AND run_key IN
        (SELECT run_key FROM team_history WHERE namespace=? AND finished=1
         ORDER BY updated_at DESC,run_key DESC LIMIT -1 OFFSET 200)
      """)
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(namespace, at: 2, to: statement)
    try finish(statement)
  }

  private func prepare(_ sql: String) throws -> OpaquePointer {
    guard let database else { throw Failure.unavailable }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Failure.unavailable }
    return statement
  }
  private func execute(_ sql: String) throws {
    guard let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.unavailable }
  }
  private func finish(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.unavailable }
  }
  private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
    _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, Self.transient) }
  }
  private func purpose(_ key: String) -> String { "team-history:\(namespace):\(key)" }
  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  static func defaultFileURL() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    return root.appendingPathComponent("GalaxySSI/AgentRecovery/team-history.sqlite3")
  }
}
