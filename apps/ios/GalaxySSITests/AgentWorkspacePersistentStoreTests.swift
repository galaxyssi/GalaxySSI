import XCTest

@testable import GalaxySSI

final class AgentWorkspacePersistentStoreTests: XCTestCase {
  func testFailedWorkspaceCommitPreservesRecordsRecoveryAndNotifications() throws {
    let fileURL = try temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    var reject = false
    var writes = 0
    let store = FileAgentWorkspaceStore(fileURL: fileURL, clock: { 2000 }, writeFile: { data, url in
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
      writes += 1
      try data.write(to: url, options: .atomic)
    })
    var notifications = 0
    let observer = NotificationCenter.default.addObserver(forName: .galaxySSIWorkspaceDidPersist, object: nil, queue: nil) {
      if ($0.object as? FileAgentWorkspaceStore) === store { notifications += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    let saved = try store.upsert(workspace("stable", status: .running))
    let original = try Data(contentsOf: fileURL)
    XCTAssertEqual(writes, 1)
    XCTAssertEqual(notifications, 1)
    reject = true
    XCTAssertThrowsError(try store.upsert(workspace("new")))
    XCTAssertThrowsError(try store.appendEvent(workspaceId: saved.workspaceId,
      event: .init(kind: AgentTaskEventKinds.progress, message: "unsaved"), expectedRevision: saved.revision))
    XCTAssertThrowsError(try store.requestCancel(saved.workspaceId, expectedRevision: saved.revision, timestampMillis: 3000))
    XCTAssertThrowsError(try store.delete(saved.workspaceId, expectedRevision: saved.revision))
    XCTAssertEqual(try Data(contentsOf: fileURL), original)
    XCTAssertEqual(writes, 1)
    XCTAssertEqual(notifications, 1)
    let reopened = FileAgentWorkspaceStore(fileURL: fileURL)
    XCTAssertEqual(reopened.list(), [saved])
    XCTAssertEqual(reopened.recoverable(), [saved])
  }

  func testInvalidWorkspaceSnapshotsCannotBeOverwrittenByMutation() throws {
    let fileURL = try temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let valid = try AgentWorkspaceJsonCodec.encode(workspace("original"))
    for raw in ["", "not JSON", #"{"version":3,"workspaces":[]}"#,
      #"{"version":true,"workspaces":[]}"#, #"{"version":2}"#,
      #"{"version":2,"workspaces":[null]}"#,
      "{\"version\":2,\"workspaces\":[\(valid),\(valid)]}",
      "{\"version\":2,\"workspaces\":[\(valid),{}]}"] {
      let original = Data(raw.utf8)
      try original.write(to: fileURL, options: .atomic)
      let store = FileAgentWorkspaceStore(fileURL: fileURL)
      XCTAssertThrowsError(try store.upsert(workspace("replacement")))
      XCTAssertThrowsError(try store.delete("workspace-original", expectedRevision: nil))
      XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }
  }

  func testPersistedWorkspaceReaderKeepsLegacyAndEmptySnapshots() throws {
    let valid = try AgentWorkspaceJsonCodec.encode(workspace("legacy"))
    for prefix in ["", "\"version\":1,", "\"version\":\"2\","] {
      XCTAssertEqual(try AgentWorkspaceJsonCodec.decodePersistedList("{\(prefix)\"workspaces\":[\(valid)]}").count, 1)
    }
    XCTAssertTrue(try AgentWorkspaceJsonCodec.decodePersistedList(AgentWorkspaceJsonCodec.emptyDocument()).isEmpty)
  }

  func testWorkspaceInstancesShareRevisionCompareAndCommit() throws {
    let fileURL = try temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let stores = [FileAgentWorkspaceStore(fileURL: fileURL), FileAgentWorkspaceStore(fileURL: fileURL)]
    let saved = try stores[0].upsert(workspace("shared", status: .running))
    let resultsLock = NSLock()
    var successes = 0
    var conflicts = 0
    var unexpected: [String] = []
    DispatchQueue.concurrentPerform(iterations: stores.count) { index in
      do {
        _ = try stores[index].appendEvent(workspaceId: saved.workspaceId,
          event: .init(kind: AgentTaskEventKinds.progress, message: String(index)), expectedRevision: saved.revision)
        resultsLock.lock(); successes += 1; resultsLock.unlock()
      } catch is AgentWorkspaceRevisionConflictError {
        resultsLock.lock(); conflicts += 1; resultsLock.unlock()
      } catch {
        resultsLock.lock(); unexpected.append(String(describing: error)); resultsLock.unlock()
      }
    }
    XCTAssertEqual(successes, 1)
    XCTAssertEqual(conflicts, 1)
    XCTAssertTrue(unexpected.isEmpty)
    let restored = try XCTUnwrap(stores[0].find(saved.workspaceId))
    XCTAssertEqual(restored.revision, saved.revision + 1)
    XCTAssertEqual(restored.eventJournal.count, 1)
  }

  func testWorkspaceEvictionAndRecoveryAreOneCommittedSnapshot() throws {
    let fileURL = try temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let existing = (0..<AgentWorkspaceBoundsPolicy.maxWorkspaces).map { index -> AgentWorkspace in
      var value = workspace(String(index), status: index == 0 ? .completed : .running)
      value.createdAtMillis = Int64(index + 1)
      value.updatedAtMillis = Int64(index + 1)
      return value
    }
    let original = Data(AgentWorkspaceJsonCodec.encodeList(existing).utf8)
    try original.write(to: fileURL, options: .atomic)
    var reject = true
    let store = FileAgentWorkspaceStore(fileURL: fileURL, clock: { 2000 }, writeFile: { data, url in
      if reject { throw CocoaError(.fileWriteOutOfSpace) }
      try data.write(to: url, options: .atomic)
    })
    XCTAssertThrowsError(try store.upsert(workspace("new", status: .running)))
    XCTAssertEqual(try Data(contentsOf: fileURL), original)
    XCTAssertNotNil(store.find("workspace-0"))
    reject = false
    let created = try store.upsert(workspace("new", status: .running))
    let reopened = FileAgentWorkspaceStore(fileURL: fileURL)
    XCTAssertEqual(reopened.list().count, AgentWorkspaceBoundsPolicy.maxWorkspaces)
    XCTAssertNil(reopened.find("workspace-0"))
    XCTAssertEqual(reopened.find(created.workspaceId), created)
    XCTAssertEqual(Set(reopened.recoverable().map(\.workspaceId)), Set(reopened.list().map(\.workspaceId)))
  }

  func testFileStorePersistsRecoverableWorkspaceMutationsAcrossInstances() throws {
    let fileURL = try temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    var now: Int64 = 1_000
    let store = FileAgentWorkspaceStore(fileURL: fileURL, clock: { now })

    let created = try store.upsert(workspace("persisted", status: .running))
    XCTAssertEqual(created.revision, 1)

    let restored = FileAgentWorkspaceStore(fileURL: fileURL, clock: { now })
    XCTAssertEqual(restored.find("workspace-persisted")?.status, .running)

    now = 1_100
    let evented = try XCTUnwrap(restored.appendEvent(
      workspaceId: "workspace-persisted",
      kind: AgentTaskEventKinds.progress,
      message: "downloaded",
      expectedRevision: created.revision
    ))
    XCTAssertEqual(evented.revision, 2)
    XCTAssertEqual(evented.eventJournal.single?.message, "downloaded")

    let recovered = FileAgentWorkspaceStore(fileURL: fileURL, clock: { now }).recoverable()
    XCTAssertEqual(recovered.map(\.workspaceId), ["workspace-persisted"])
    XCTAssertEqual(recovered.single?.revision, 2)
  }

  func testFileStorePreservesRevisionConflictsAndClear() throws {
    let fileURL = try temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
    let store = FileAgentWorkspaceStore(fileURL: fileURL, clock: { 2_000 })
    let created = try store.upsert(workspace("conflict"))

    XCTAssertThrowsError(try store.upsert(created, expectedRevision: 0)) { error in
      XCTAssertTrue(error is AgentWorkspaceRevisionConflictError)
    }

    let restored = FileAgentWorkspaceStore(fileURL: fileURL, clock: { 2_000 })
    XCTAssertThrowsError(try restored.delete("workspace-conflict", expectedRevision: 0)) { error in
      XCTAssertTrue(error is AgentWorkspaceRevisionConflictError)
    }

    XCTAssertTrue(try restored.delete("workspace-conflict", expectedRevision: created.revision))
    XCTAssertTrue(FileAgentWorkspaceStore(fileURL: fileURL, clock: { 2_000 }).list().isEmpty)

    _ = try restored.upsert(workspace("after-clear"))
    restored.clear()
    XCTAssertTrue(FileAgentWorkspaceStore(fileURL: fileURL, clock: { 2_000 }).list().isEmpty)
  }

  private func workspace(
    _ suffix: String,
    status: AgentWorkspaceStatus = .created
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace-\(suffix)",
      sessionId: "session-\(suffix)",
      conversationId: "conversation-\(suffix)",
      taskId: "task-\(suffix)",
      status: status
    )
  }

  private func temporaryFileURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("GalaxySSI-AgentWorkspacePersistentStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("workspaces.json", isDirectory: false)
  }
}
