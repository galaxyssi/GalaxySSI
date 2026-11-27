import Foundation
import XCTest
@testable import GalaxySSI

final class AgentWorkspacePersistenceTests: XCTestCase {
  func testMissingFileIsEmptyAndCheckedSaveReopens() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileAgentWorkspaceNativeToolStateStore(fileURL: root.appendingPathComponent("state.json"))
    XCTAssertTrue(try store.loadChecked().isEmpty)
    try store.saveChecked(Self.seed)
    XCTAssertEqual(try store.loadChecked(), Self.seed)
  }

  func testCorruptFileCannotBeReplacedByCheckedOrLegacySave() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json")
    let store = FileAgentWorkspaceNativeToolStateStore(fileURL: url)
    for content in ["not-json", "[]"] {
      let corrupt = Data(content.utf8)
      try corrupt.write(to: url)
      XCTAssertThrowsError(try store.loadChecked())
      XCTAssertThrowsError(try store.saveChecked(Self.seed))
      store.save(Self.seed)
      XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
  }

  func testUnreadableFileShapeDoesNotBecomeAnEmptySnapshot() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileAgentWorkspaceNativeToolStateStore(fileURL: root)
    XCTAssertThrowsError(try store.loadChecked())
    XCTAssertThrowsError(try store.saveChecked(Self.seed))
    var directory: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &directory))
    XCTAssertTrue(directory.boolValue)
  }

  func testExecutorRejectsCorruptRestoreAndRetriesOnlyAfterRepair() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("state.json")
    let corrupt = Data("broken".utf8)
    try corrupt.write(to: url)
    let executor = AgentWorkspaceNativeToolExecutor(stateStore: FileAgentWorkspaceNativeToolStateStore(fileURL: url))
    let registry = try Self.registry(executor)
    XCTAssertFalse(Self.call(registry, tool: AgentPhoneNativeToolCatalog.workspaceInitialize).isSuccess)
    XCTAssertEqual(try Data(contentsOf: url), corrupt)
    try JSONEncoder().encode(Self.seed).write(to: url, options: .atomic)
    XCTAssertEqual(Self.call(registry, tool: AgentPhoneNativeToolCatalog.workspaceReadText,
      input: ["path": .string("retained.txt")]).output["text"], .string("retained"))
  }

  func testCheckedSaveFailureRollsBackMemoryAndDoesNotReportSuccess() throws {
    let saved = CheckedStore()
    let registry = try Self.registry(AgentWorkspaceNativeToolExecutor(stateStore: saved))
    let write: AgentMcpJSONObject = ["path": .string("new.txt"), "text": .string("new")]
    XCTAssertFalse(Self.call(registry, tool: AgentPhoneNativeToolCatalog.workspaceWriteText, input: write).isSuccess)
    XCTAssertFalse(Self.call(registry, tool: AgentPhoneNativeToolCatalog.workspaceReadText,
      input: ["path": .string("new.txt")]).isSuccess)
    XCTAssertEqual(saved.table, Self.seed)
    XCTAssertEqual(saved.saves, 1)
    saved.rejectWrites = false
    XCTAssertTrue(Self.call(registry, tool: AgentPhoneNativeToolCatalog.workspaceWriteText, input: write).isSuccess)
    XCTAssertEqual(saved.table["seed"]?["new.txt"]?.data(), Data("new".utf8))
    XCTAssertEqual(saved.table["seed"]?["retained.txt"]?.data(), Data("retained".utf8))
    XCTAssertEqual(saved.saves, 2)
  }

  func testFailedOperationDoesNotPersistItsImplicitWorkspace() throws {
    let saved = CheckedStore()
    saved.table = [:]
    saved.rejectWrites = false
    let registry = try Self.registry(AgentWorkspaceNativeToolExecutor(stateStore: saved))
    XCTAssertFalse(Self.call(registry, tool: AgentPhoneNativeToolCatalog.workspaceWriteText,
      input: ["path": .string("../escape"), "text": .string("new")]).isSuccess)
    XCTAssertTrue(saved.table.isEmpty)
    XCTAssertEqual(saved.saves, 0)
    XCTAssertTrue(Self.call(registry, tool: AgentPhoneNativeToolCatalog.workspaceInitialize).isSuccess)
    XCTAssertEqual(saved.saves, 1)
  }

  private static var seed: [String: [String: AgentWorkspaceNativeToolStoredEntry]] {
    ["seed": ["": .init(type: .directory, data: Data(), modifiedAtMillis: 1),
      "retained.txt": .init(type: .file, data: Data("retained".utf8), modifiedAtMillis: 1)]]
  }

  private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private static func registry(_ executor: AgentWorkspaceNativeToolExecutor) throws -> AgentNativeToolRegistry {
    try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: executor))
  }

  private static func call(_ registry: AgentNativeToolRegistry, tool: String,
                           input: AgentMcpJSONObject = [:]) -> AgentNativeToolResult {
    registry.invoke(tool, input: input.merging(["workspace_id": .string("seed")]) { _, host in host },
      context: .init(invocationId: UUID().uuidString,
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent, AgentPhoneNativeToolCatalog.workspaceWriteConsent]))
  }

  private final class CheckedStore: AgentWorkspaceNativeToolCheckedStateStore {
    var table = AgentWorkspacePersistenceTests.seed
    var rejectWrites = true
    var saves = 0
    func load() -> [String: [String: AgentWorkspaceNativeToolStoredEntry]] {
      XCTFail("The executor must use the checked read")
      return [:]
    }
    func save(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]]) {
      XCTFail("The executor must use the checked write")
    }
    func loadChecked() throws -> [String: [String: AgentWorkspaceNativeToolStoredEntry]] { table }
    func saveChecked(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]]) throws {
      saves += 1
      if rejectWrites { throw CocoaError(.fileWriteNoPermission) }
      table = workspaces
    }
    func clear() { table = [:] }
  }
}
