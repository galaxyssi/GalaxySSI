import CryptoKit
import XCTest

@testable import GalaxySSI

final class AgentWorkspaceIndexedStoreTests: XCTestCase {
  func testLegacyImportRetiresPlaintextAndScopesBodyDecoding() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("workspaces.json"), secrets = InMemorySecretStore()
    let values = (0..<64).map { workspace(String($0), status: $0 < 2 ? .running : .completed, time: Int64($0 + 1)) }
    try Data(AgentWorkspaceJsonCodec.encodeList(values).utf8).write(to: file)
    var decodes = 0
    let store = IndexedAgentWorkspaceStore(legacyURL: file, secrets: secrets, didDecodeBody: { decodes += 1 })
    XCTAssertEqual(store.list().count, 64)
    XCTAssertFalse(store.legacyCleanupPending)
    decodes = 0
    XCTAssertEqual(store.find(values[0].workspaceId), values[0])
    XCTAssertEqual(decodes, 1)
    decodes = 0
    XCTAssertEqual(Set(store.recoverable().map(\.workspaceId)), Set(values.prefix(2).map(\.workspaceId)))
    XCTAssertEqual(decodes, 2)
    decodes = 0
    _ = try store.appendEvent(workspaceId: values[0].workspaceId,
      event: .init(kind: AgentTaskEventKinds.progress, message: "private progress"), expectedRevision: values[0].revision)
    XCTAssertEqual(decodes, 1, "Mutation must not decode unrelated plans or events")
    for path in [IndexedAgentWorkspaceStore.databaseURL(for: file).path,
      IndexedAgentWorkspaceStore.databaseURL(for: file).path + "-wal"] where FileManager.default.fileExists(atPath: path) {
      let raw = try Data(contentsOf: URL(fileURLWithPath: path))
      XCTAssertNil(raw.range(of: Data("private progress".utf8)))
      XCTAssertNil(raw.range(of: Data(values[0].workspaceId.utf8)))
    }
  }

  func testIndexedMutationsKeepReferenceReducerAndRecoveryBehavior() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = IndexedAgentWorkspaceStore(legacyURL: root.appendingPathComponent("workspaces.json"),
      secrets: InMemorySecretStore(), clock: { 2_000 })
    let reference = InMemoryAgentWorkspaceStore(clock: { 2_000 })
    let input = workspace("shared", status: .running)
    var actual = try store.upsert(input, expectedRevision: 0)
    var expected = try reference.upsert(input, expectedRevision: 0)
    XCTAssertEqual(actual, expected)
    let event = AgentWorkspaceEvent(kind: AgentTaskEventKinds.progress, message: "progress")
    actual = try XCTUnwrap(store.appendEvent(workspaceId: input.workspaceId, event: event, expectedRevision: actual.revision))
    expected = try XCTUnwrap(reference.appendEvent(workspaceId: input.workspaceId, event: event, expectedRevision: expected.revision))
    let checkpoint = AgentWorkspaceCheckpoint(id: "checkpoint", planSnapshot: "plan", stateJson: "{}")
    actual = try XCTUnwrap(store.checkpoint(workspaceId: input.workspaceId, checkpoint: checkpoint, expectedRevision: actual.revision))
    expected = try XCTUnwrap(reference.checkpoint(workspaceId: input.workspaceId, checkpoint: checkpoint, expectedRevision: expected.revision))
    XCTAssertEqual(actual, expected)
    XCTAssertEqual(store.recoverable(), reference.recoverable())
    actual = try XCTUnwrap(store.requestCancel(input.workspaceId, expectedRevision: actual.revision, timestampMillis: 3_000))
    expected = try XCTUnwrap(reference.requestCancel(input.workspaceId, expectedRevision: expected.revision, timestampMillis: 3_000))
    XCTAssertEqual(actual, expected)
    XCTAssertEqual(store.recoverable(), reference.recoverable())
    XCTAssertThrowsError(try store.delete(input.workspaceId, expectedRevision: 0))
    XCTAssertTrue(try store.delete(input.workspaceId, expectedRevision: actual.revision))
    XCTAssertTrue(store.list().isEmpty)
  }

  func testMigrationRollbackRetryAndCommittedMarkerPreventResurrection() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("workspaces.json"), secrets = InMemorySecretStore()
    let old = workspace("legacy", status: .running)
    let legacy = Data(AgentWorkspaceJsonCodec.encodeList([old]).utf8)
    try legacy.write(to: file)
    var reject = true
    let store = IndexedAgentWorkspaceStore(legacyURL: file, secrets: secrets, beforeCommit: {
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
    })
    XCTAssertThrowsError(try store.upsert(workspace("new"), expectedRevision: 0))
    XCTAssertEqual(try Data(contentsOf: file), legacy)
    let accounts = IndexedAgentWorkspaceStore.accounts(for: IndexedAgentWorkspaceStore.storageIdentity(for: file))
    XCTAssertEqual(secrets.string(account: accounts.receipt), "pending")
    reject = false
    XCTAssertEqual(store.find(old.workspaceId), old)
    XCTAssertEqual(secrets.string(account: accounts.receipt), "1")
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    store.clear()
    try legacy.write(to: file)
    XCTAssertTrue(store.list().isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }

  func testFailedIndexCommitPreservesEvictionRecoveryAndNotifications() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("workspaces.json"), secrets = InMemorySecretStore()
    let old = (0..<64).map { workspace(String($0), status: .running, time: Int64($0 + 1)) }
    try Data(AgentWorkspaceJsonCodec.encodeList(old).utf8).write(to: file)
    var reject = false, notifications = 0
    var samples: [AgentWorkspaceCreationTiming.Sample] = []
    let store = IndexedAgentWorkspaceStore(legacyURL: file, secrets: secrets, clock: { 2_000 }, timingSink: { samples.append($0) },
      beforeCommit: { if reject { throw CocoaError(.fileWriteOutOfSpace) } })
    let original = store.list()
    let observer = NotificationCenter.default.addObserver(forName: .galaxySSIWorkspaceDidPersist, object: nil, queue: nil) {
      if ($0.object as? IndexedAgentWorkspaceStore) === store { notifications += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    reject = true
    XCTAssertThrowsError(try store.upsert(workspace("new", status: .running), expectedRevision: 0))
    XCTAssertThrowsError(try store.requestCancel(old[0].workspaceId, expectedRevision: old[0].revision, timestampMillis: 3_000))
    XCTAssertThrowsError(try store.delete(old[0].workspaceId, expectedRevision: old[0].revision))
    store.clear()
    let reopened = IndexedAgentWorkspaceStore(legacyURL: file, secrets: secrets)
    XCTAssertEqual(reopened.list(), original)
    XCTAssertEqual(reopened.recoverable(), original)
    XCTAssertEqual(notifications, 0)
    XCTAssertTrue(samples.isEmpty)
    reject = false
    _ = try store.upsert(workspace("new", status: .running), expectedRevision: 0)
    XCTAssertNil(store.find(old[0].workspaceId))
    XCTAssertEqual(store.list().count, 64)
    XCTAssertEqual(notifications, 1)
    XCTAssertEqual(samples.map(\.storage), [.indexedTransaction])
  }

  func testIndependentDatabaseHandlesCompareRevisionInsideTheTransaction() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("index/workspaces.sqlite"), master = SymmetricKey(size: .bits256)
    let handles = try (0..<2).map { _ in try AgentWorkspaceIndexDatabase(url: url, master: master, identity: "fixture") }
    let old = workspace("shared", status: .running)
    try handles[0].initialize(allowImport: true) { [old] }
    try handles[1].initialize(allowImport: false) { XCTFail("Must not import again"); return [] }
    let resultsLock = NSLock()
    var successes = 0, conflicts = 0, failures: [String] = []
    DispatchQueue.concurrentPerform(iterations: 2) { index in
      do {
        try handles[index].transaction {
          let current = try XCTUnwrap(handles[index].workspace(old.workspaceId))
          let reducer = InMemoryAgentWorkspaceStore(initialWorkspaces: [current], clock: { 2_000 })
          let updated = try XCTUnwrap(reducer.appendEvent(workspaceId: old.workspaceId,
            event: .init(kind: AgentTaskEventKinds.progress, message: String(index)), expectedRevision: old.revision))
          try handles[index].persist(updated)
        }
        resultsLock.lock(); successes += 1; resultsLock.unlock()
      } catch is AgentWorkspaceRevisionConflictError {
        resultsLock.lock(); conflicts += 1; resultsLock.unlock()
      } catch {
        resultsLock.lock(); failures.append(String(describing: error)); resultsLock.unlock()
      }
    }
    XCTAssertEqual(successes, 1)
    XCTAssertEqual(conflicts, 1)
    XCTAssertTrue(failures.isEmpty)
    XCTAssertEqual(try handles[0].workspace(old.workspaceId)?.revision, old.revision + 1)
  }

  func testCommittedKeyOrIndexLossCannotCreateReplacementOrReimport() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("workspaces.json"), secrets = InMemorySecretStore()
    let store = IndexedAgentWorkspaceStore(legacyURL: file, secrets: secrets)
    _ = try store.upsert(workspace("private"), expectedRevision: 0)
    let accounts = IndexedAgentWorkspaceStore.accounts(for: IndexedAgentWorkspaceStore.storageIdentity(for: file))
    let key = try XCTUnwrap(secrets.string(account: accounts.key))
    secrets.delete(account: accounts.key)
    XCTAssertThrowsError(try store.upsert(workspace("replacement"), expectedRevision: 0))
    XCTAssertNil(secrets.string(account: accounts.key))
    try secrets.setString(key, account: accounts.key)
    let legacy = Data(AgentWorkspaceJsonCodec.encodeList([workspace("stale")]).utf8)
    try legacy.write(to: file)
    try FileManager.default.removeItem(at: IndexedAgentWorkspaceStore.databaseURL(for: file).deletingLastPathComponent())
    XCTAssertThrowsError(try store.upsert(workspace("replacement"), expectedRevision: 0))
    XCTAssertEqual(try Data(contentsOf: file), legacy)
    XCTAssertFalse(FileManager.default.fileExists(atPath: IndexedAgentWorkspaceStore.databaseURL(for: file).path))
  }

  func testIndexedRetentionMatchesCountSizeAndTiePolicies() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = IndexedAgentWorkspaceStore(legacyURL: root.appendingPathComponent("workspaces.json"),
      secrets: InMemorySecretStore(), clock: { 2_000 })
    let reference = InMemoryAgentWorkspaceStore(clock: { 2_000 })
    for index in 0..<66 {
      let value = workspace(String(format: "%03d", index), status: index % 3 == 0 ? .completed : .running)
      _ = try store.upsert(value, expectedRevision: 0)
      _ = try reference.upsert(value, expectedRevision: 0)
    }
    XCTAssertEqual(store.list(), reference.list())
    for index in 0..<3 {
      var value = workspace("large-" + String(index), status: index == 1 ? .completed : .running, time: 3_000 + Int64(index))
      value.goal = String(repeating: "\u{0001}", count: AgentWorkspaceBoundsPolicy.maxGoalCharacters)
      value.eventJournal = (1...100).map { AgentWorkspaceEvent(sequence: Int64($0), kind: "progress",
        message: String(repeating: "\u{0001}", count: 1_024), payloadJson: String(repeating: "\u{0001}", count: 4_096), timestampMillis: 1) }
      value.eventSequence = 100
      value.resultJson = String(repeating: "\u{0001}", count: AgentWorkspaceBoundsPolicy.maxResultJsonCharacters)
      if index == 0 {
        value.toolCalls = (0..<50).map { AgentWorkspaceToolCallRecord(id: "call-" + String($0), toolName: "fixture",
          resultJson: String(repeating: "\u{0001}", count: AgentWorkspaceBoundsPolicy.maxToolResultCharacters)) }
        XCTAssertGreaterThan(AgentWorkspaceJsonCodec.encodeList([value]).count, AgentWorkspaceJsonCodec.maxSerializedCharacters,
          "Fixture must exercise single-record shrinking, not only count retention")
      }
      _ = try store.upsert(value, expectedRevision: 0)
      _ = try reference.upsert(value, expectedRevision: 0)
      XCTAssertEqual(store.list(), reference.list())
      XCTAssertEqual(store.recoverable(), reference.recoverable())
    }
  }

  func testWrongNamespaceAndMalformedLegacyAreRejectedWithoutOverwrite() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("index/workspaces.sqlite"), master = SymmetricKey(size: .bits256)
    let first = try AgentWorkspaceIndexDatabase(url: url, master: master, identity: "first")
    try first.initialize(allowImport: true) { [workspace("private")] }
    let wrong = try AgentWorkspaceIndexDatabase(url: url, master: master, identity: "wrong")
    XCTAssertThrowsError(try wrong.initialize(allowImport: true) { [] })
    let file = root.appendingPathComponent("malformed.json"), secrets = InMemorySecretStore()
    let raw = Data(#"{"version":2,"workspaces":[null]}"#.utf8)
    try raw.write(to: file)
    let store = IndexedAgentWorkspaceStore(legacyURL: file, secrets: secrets)
    XCTAssertThrowsError(try store.upsert(workspace("replacement"), expectedRevision: 0))
    XCTAssertEqual(try Data(contentsOf: file), raw)
  }

  private func workspace(_ id: String, status: AgentWorkspaceStatus = .created, time: Int64 = 1) -> AgentWorkspace {
    var value = AgentWorkspace(workspaceId: "workspace-" + id, sessionId: "session-" + id,
      conversationId: "conversation-" + id, taskId: "task-" + id, status: status)
    value.createdAtMillis = time
    value.updatedAtMillis = time
    value.revision = 1
    return AgentWorkspaceBoundsPolicy.normalizeOrNil(value)!
  }
  private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalaxySSI-WorkspaceIndex-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}
