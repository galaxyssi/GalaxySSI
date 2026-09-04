import XCTest

@testable import GalaxySSI

final class AgentWorkspacePersistentStoreTests: XCTestCase {
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
