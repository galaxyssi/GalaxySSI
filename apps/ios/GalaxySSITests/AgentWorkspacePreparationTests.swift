import Foundation
import XCTest
@testable import GalaxySSI

final class AgentWorkspacePreparationTests: XCTestCase {
  func testExplicitStoreKeepsEagerPreparationByDefault() {
    let saved = Store()
    let executor = AgentWorkspaceNativeToolExecutor(stateStore: saved)
    XCTAssertEqual(saved.loads, 1)
    XCTAssertEqual(saved.saves, 0)
    withExtendedLifetime(executor) {}
  }

  func testBackgroundPreparationDoesNotReadOnConstructorThread() throws {
    let queue = DispatchQueue(label: "workspace-preparation-fixture")
    queue.suspend()
    var suspended = true
    defer { if suspended { queue.resume() } }
    let loaded = expectation(description: "Background read")
    let saved = Store {
      XCTAssertFalse(Thread.isMainThread)
      loaded.fulfill()
    }
    let executor = AgentWorkspaceNativeToolExecutor(stateStore: saved, preparationQueue: queue)
    XCTAssertEqual(saved.loads, 0)
    queue.resume()
    suspended = false
    wait(for: [loaded], timeout: 3)
    let registry = try Self.registry(executor)
    XCTAssertEqual(Self.read(registry).output["text"], .string("retained"))
    XCTAssertEqual(saved.loads, 1)
    XCTAssertEqual(saved.saves, 0)
  }

  func testFirstInvocationPreparesOnceBeforeAnyMutation() throws {
    let queue = DispatchQueue(label: "workspace-early-use-fixture")
    queue.suspend()
    var suspended = true
    defer { if suspended { queue.resume() } }
    let saved = Store()
    let executor = AgentWorkspaceNativeToolExecutor(stateStore: saved, preparationQueue: queue)
    let registry = try Self.registry(executor)
    XCTAssertTrue(Self.write(registry, path: "new.txt").isSuccess)
    let drained = expectation(description: "Queued preparation drained")
    queue.async { drained.fulfill() }
    queue.resume()
    suspended = false
    wait(for: [drained], timeout: 3)
    XCTAssertEqual(saved.loads, 1)
    XCTAssertEqual(saved.saves, 1)
    XCTAssertEqual(Self.read(registry).output["text"], .string("retained"))
    XCTAssertEqual(saved.snapshot["seed"]?["new.txt"]?.data(), Data("new".utf8))
  }

  func testMutationWaitsForInFlightRestoreAndRetainsOldFiles() throws {
    let entered = expectation(description: "Restore entered")
    let gate = DispatchSemaphore(value: 0)
    defer { gate.signal() }
    let saved = Store {
      entered.fulfill()
      XCTAssertEqual(gate.wait(timeout: .now() + 3), .success)
    }
    let executor = AgentWorkspaceNativeToolExecutor(stateStore: saved,
      preparationQueue: DispatchQueue(label: "workspace-blocked-restore-fixture"))
    let registry = try Self.registry(executor)
    wait(for: [entered], timeout: 3)
    let started = expectation(description: "Writer started")
    let finished = expectation(description: "Writer finished")
    DispatchQueue(label: "workspace-writer-fixture").async {
      started.fulfill()
      XCTAssertTrue(Self.write(registry, path: "after.txt").isSuccess)
      finished.fulfill()
    }
    wait(for: [started], timeout: 3)
    XCTAssertEqual(saved.saves, 0)
    gate.signal()
    wait(for: [finished], timeout: 3)
    XCTAssertEqual(saved.loads, 1)
    XCTAssertEqual(saved.snapshot["seed"]?["retained.txt"]?.data(), Data("retained".utf8))
    XCTAssertEqual(saved.snapshot["seed"]?["after.txt"]?.data(), Data("new".utf8))
  }

  func testIndependentRegistriesSharingExecutorDoNotLoseConcurrentWrites() throws {
    let saved = Store()
    let executor = AgentWorkspaceNativeToolExecutor(stateStore: saved)
    let registries = try (0..<16).map { _ in try Self.registry(executor) }
    DispatchQueue.concurrentPerform(iterations: registries.count) { index in
      XCTAssertTrue(Self.write(registries[index], path: "file-\(index).txt").isSuccess)
    }
    XCTAssertEqual(saved.loads, 1)
    XCTAssertEqual(saved.saves, 16)
    XCTAssertEqual(saved.snapshot["seed"]?.count, 18)
  }

  func testDeniedInvocationDoesNotForceQueuedRestoreOrMutateState() throws {
    let queue = DispatchQueue(label: "workspace-denied-fixture")
    queue.suspend()
    var suspended = true
    defer { if suspended { queue.resume() } }
    let saved = Store()
    let executor = AgentWorkspaceNativeToolExecutor(stateStore: saved, preparationQueue: queue)
    let registry = try Self.registry(executor)
    let result = registry.invoke(AgentPhoneNativeToolCatalog.workspaceWriteText,
      input: ["workspace_id": .string("seed"), "path": .string("denied.txt"), "text": .string("new")],
      context: AgentNativeToolInvocationContext(invocationId: "denied"))
    XCTAssertFalse(result.isSuccess)
    XCTAssertEqual(saved.loads, 0)
    XCTAssertEqual(saved.saves, 0)
    let drained = expectation(description: "Preparation drained")
    queue.async { drained.fulfill() }
    queue.resume()
    suspended = false
    wait(for: [drained], timeout: 3)
    XCTAssertEqual(saved.saves, 0)
  }

  private static func registry(_ executor: AgentWorkspaceNativeToolExecutor) throws -> AgentNativeToolRegistry {
    try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: executor))
  }

  private static func write(_ registry: AgentNativeToolRegistry, path: String) -> AgentNativeToolResult {
    registry.invoke(AgentPhoneNativeToolCatalog.workspaceWriteText,
      input: ["workspace_id": .string("seed"), "path": .string(path), "text": .string("new")],
      context: .init(invocationId: UUID().uuidString,
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]))
  }

  private static func read(_ registry: AgentNativeToolRegistry) -> AgentNativeToolResult {
    registry.invoke(AgentPhoneNativeToolCatalog.workspaceReadText,
      input: ["workspace_id": .string("seed"), "path": .string("retained.txt")],
      context: .init(invocationId: UUID().uuidString,
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]))
  }

  private final class Store: AgentWorkspaceNativeToolStateStore {
    private let lock = NSLock()
    private var loadCount = 0
    private var saveCount = 0
    private var table: [String: [String: AgentWorkspaceNativeToolStoredEntry]] = ["seed": [
      "": .init(type: .directory, data: Data(), modifiedAtMillis: 1),
      "retained.txt": .init(type: .file, data: Data("retained".utf8), modifiedAtMillis: 1)
    ]]
    private let onLoad: () -> Void
    init(onLoad: @escaping () -> Void = {}) { self.onLoad = onLoad }
    var loads: Int { lock.lock(); defer { lock.unlock() }; return loadCount }
    var saves: Int { lock.lock(); defer { lock.unlock() }; return saveCount }
    var snapshot: [String: [String: AgentWorkspaceNativeToolStoredEntry]] {
      lock.lock(); defer { lock.unlock() }; return table
    }
    func load() -> [String: [String: AgentWorkspaceNativeToolStoredEntry]] {
      lock.lock()
      loadCount += 1
      let result = table
      lock.unlock()
      onLoad()
      return result
    }
    func save(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]]) {
      lock.lock(); defer { lock.unlock() }
      saveCount += 1
      table = workspaces
    }
    func clear() { lock.lock(); defer { lock.unlock() }; table = [:] }
  }
}
