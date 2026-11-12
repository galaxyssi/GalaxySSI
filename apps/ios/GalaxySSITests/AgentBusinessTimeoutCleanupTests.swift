import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class AgentBusinessTimeoutCleanupTests: XCTestCase {
  private struct Catalog: Codable {
    let catalogSHA256: String
  }

  private struct Turn: Codable {
    var state: String
    var workspace: AgentWorkspaceKey
    var goal: String
    let createdAtMillis: Int64

    func matches(_ current: AgentWorkspace) -> Bool {
      current.key == workspace && Data(current.goal.utf8) == Data(goal.utf8) &&
        current.createdAtMillis == createdAtMillis && current.remoteRunId.isEmpty
    }
  }

  private struct Report: Codable {
    var catalogSHA256: String
    var caseID: String
    var windowKey: String
    var device: String
    var turns: [Turn]
  }

  private struct Receipt: Codable {
    let reportSHA256: String
    let turnIndex: Int
    let workspace: AgentWorkspaceKey
    let originalState: String
    let statusBefore: AgentWorkspaceStatus
    var cancellationRequested = false
    var statusAfter: AgentWorkspaceStatus?
    var executionStopped = false
  }

  private enum Failure: Error { case invalidScope, taskStillActive }

  @MainActor func testOptInCancelRecordedBusinessTimeout() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["GALAXYSSI_BUSINESS_CANCEL_RECORDED"] == "1" else {
      throw XCTSkip("Explicit recorded business timeout cleanup is not enabled.")
    }
    let run = try XCTUnwrap(env["GALAXYSSI_BUSINESS_RUN"])
    let caseID = try XCTUnwrap(env["GALAXYSSI_BUSINESS_CASE"])
    let index = try XCTUnwrap(env["GALAXYSSI_BUSINESS_TURN_INDEX"].flatMap { Int($0) })
    let device = try XCTUnwrap(UIDevice.current.identifierForVendor?.uuidString)
    guard Self.valid(run: run, caseID: caseID) else { throw Failure.invalidScope }
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    let directory = support.appendingPathComponent("XCTest-BusinessScenarios", isDirectory: true)
      .appendingPathComponent(run, isDirectory: true)
    let workspaceFile = directory.appendingPathComponent("synthetic-workspaces.json")
    let report = try Self.read(directory.appendingPathComponent(caseID + ".json"))
    let catalog = try JSONDecoder().decode(Catalog.self, from: Self.read(directory.appendingPathComponent("catalog.json")))
    guard Self.digest(report) == env["GALAXYSSI_BUSINESS_REPORT_SHA256"],
          FileManager.default.fileExists(atPath: workspaceFile.path),
          workspaceFile.resolvingSymlinksInPath().path ==
            support.resolvingSymlinksInPath().appendingPathComponent("XCTest-BusinessScenarios")
              .appendingPathComponent(run).appendingPathComponent("synthetic-workspaces.json").path else {
      throw Failure.invalidScope
    }
    let store = FileAgentWorkspaceStore(fileURL: workspaceFile)
    let supervisor = AgentTaskSupervisor(workspaceStore: store)
    defer { supervisor.close() }
    let receipt = try await Self.clean(report: report, catalog: catalog, run: run, caseID: caseID, index: index,
      device: device, store: store, supervisor: supervisor, directory: directory)
    XCTAssertTrue(receipt.executionStopped)
  }

  private static func valid(run: String, caseID: String) -> Bool {
    run.range(of: #"\A[A-Za-z0-9_-]{1,64}\z"#, options: .regularExpression) != nil &&
      caseID.range(of: #"\AA[0-9]{3}\z"#, options: .regularExpression) != nil
  }

  private static func read(_ url: URL) throws -> Data {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let limit = 2 * 1024 * 1024
    let data = try file.read(upToCount: limit + 1) ?? Data()
    guard !data.isEmpty, data.count <= limit else { throw Failure.invalidScope }
    return data
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func check(_ report: Report, catalog: Catalog, run: String, caseID: String, index: Int,
                            device: String, store: AgentWorkspaceStore) throws -> (Turn, AgentWorkspace) {
    guard valid(run: run, caseID: caseID), report.caseID == caseID, report.windowKey == "business-\(run)-\(caseID)",
          !device.isEmpty, report.device == device, report.catalogSHA256 == catalog.catalogSHA256,
          catalog.catalogSHA256.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil,
          report.turns.indices.contains(index) else { throw Failure.invalidScope }
    let turn = report.turns[index]
    guard turn.state == "observation_timeout", turn.workspace.conversationId == report.windowKey,
          !turn.workspace.sessionId.isEmpty, !turn.workspace.taskId.isEmpty, !turn.workspace.workspaceId.isEmpty,
          !turn.goal.isEmpty, turn.createdAtMillis > 0,
          let current = store.find(turn.workspace), turn.matches(current) else { throw Failure.invalidScope }
    return (turn, current)
  }

  private static func clean(report bytes: Data, catalog: Catalog, run: String, caseID: String, index: Int,
                            device: String, store: AgentWorkspaceStore, supervisor: AgentTaskSupervisor,
                            directory: URL) async throws -> Receipt {
    let report = try JSONDecoder().decode(Report.self, from: bytes)
    let (turn, before) = try check(report, catalog: catalog, run: run, caseID: caseID, index: index,
      device: device, store: store)
    let path = directory.appendingPathComponent("\(caseID)-\(index)-cleanup-\(UUID().uuidString).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var receipt = Receipt(reportSHA256: digest(bytes), turnIndex: index, workspace: before.key,
      originalState: turn.state, statusBefore: before.status)
    try encoder.encode(receipt).write(to: path, options: .withoutOverwriting)
    if !before.status.isTerminal {
      receipt.cancellationRequested = supervisor.cancelWorkspace(matching: before,
        reason: "Explicit cleanup of a recorded synthetic business timeout")
      try encoder.encode(receipt).write(to: path, options: .atomic)
    }
    let started = DispatchTime.now().uptimeNanoseconds
    while supervisor.activeTaskIds().contains(before.taskId),
          DispatchTime.now().uptimeNanoseconds - started < 30_000_000_000 {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    if let after = store.find(before.key), turn.matches(after) {
      receipt.statusAfter = after.status
      receipt.executionStopped = after.status.isTerminal && !supervisor.activeTaskIds().contains(before.taskId)
    }
    try encoder.encode(receipt).write(to: path, options: .atomic)
    guard receipt.executionStopped else { throw Failure.taskStillActive }
    return receipt
  }

  func testCleanupStopsOnlyTheRecordedTaskAndPreservesTheReport() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = FileAgentWorkspaceStore(fileURL: directory.appendingPathComponent("synthetic-workspaces.json"))
    let supervisor = AgentTaskSupervisor(workspaceStore: store)
    defer { supervisor.close() }
    let tracked = try supervisor.submit(workspace: workspace("tracked")) { _ in
      try await Task.sleep(nanoseconds: 60_000_000_000)
    }
    let other = try supervisor.submit(workspace: workspace("other")) { _ in
      try await Task.sleep(nanoseconds: 60_000_000_000)
    }
    let catalog = Catalog(catalogSHA256: String(repeating: "a", count: 64))
    let saved = try XCTUnwrap(store.find(tracked.workspaceId))
    let turn = Turn(state: "observation_timeout", workspace: saved.key, goal: saved.goal,
      createdAtMillis: saved.createdAtMillis)
    var report = Report(catalogSHA256: catalog.catalogSHA256, caseID: "A005", windowKey: saved.conversationId,
      device: "fixture-device", turns: [turn])
    func validate(_ candidate: Report, index: Int = 0) throws {
      _ = try Self.check(candidate, catalog: catalog, run: "run", caseID: "A005", index: index,
        device: "fixture-device", store: store)
    }
    XCTAssertThrowsError(try validate(report, index: 1))
    let changes: [(inout Report) -> Void] = [
      { $0.device = "different-device" }, { $0.caseID = "A006" }, { $0.windowKey = "other-run" },
      { $0.catalogSHA256 = String(repeating: "b", count: 64) }, { $0.turns[0].state = "submitted" },
      { $0.turns[0].goal = "Different fixture" }, { $0.turns[0].workspace.sessionId = "different-session" },
      { $0.turns[0].workspace.taskId = "task-other" }, { $0.turns[0].workspace.conversationId = "different-group" },
      { $0.turns[0].workspace.workspaceId = other.workspaceId }
    ]
    for change in changes {
      var changed = report
      change(&changed)
      XCTAssertThrowsError(try validate(changed))
    }
    var stale = saved
    stale.revision -= 1
    XCTAssertFalse(supervisor.cancelWorkspace(matching: stale, reason: "Stale fixture"))
    XCTAssertFalse(tracked.cancellationSource.isCancellationRequested)
    // Wait for the running transition before testing cancellation against its exact revision.
    let start = DispatchTime.now().uptimeNanoseconds
    while store.find(tracked.workspaceId)?.status != .running,
          DispatchTime.now().uptimeNanoseconds - start < 3_000_000_000 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(store.find(tracked.workspaceId)?.status, .running)
    let bytes = try JSONEncoder().encode(report)
    let path = directory.appendingPathComponent("A005.json")
    try bytes.write(to: path)
    let receipt = try await Self.clean(report: bytes, catalog: catalog, run: "run", caseID: "A005", index: 0,
      device: "fixture-device", store: store, supervisor: supervisor, directory: directory)
    XCTAssertTrue(receipt.executionStopped)
    XCTAssertTrue(receipt.cancellationRequested)
    XCTAssertEqual(receipt.statusAfter, .cancelled)
    XCTAssertFalse(other.cancellationSource.isCancellationRequested)
    XCTAssertEqual(try Data(contentsOf: path), bytes)
    let alreadyStopped = try await Self.clean(report: bytes, catalog: catalog, run: "run", caseID: "A005",
      index: 0, device: "fixture-device", store: store, supervisor: supervisor, directory: directory)
    XCTAssertTrue(alreadyStopped.executionStopped)
    XCTAssertFalse(alreadyStopped.cancellationRequested)
    XCTAssertEqual(alreadyStopped.statusBefore, .cancelled)
    report.turns[0].state = "completed"
    XCTAssertThrowsError(try validate(report))
    _ = other.cancel()
    await tracked.join()
    await other.join()
    await supervisor.shutdown()
  }

  private func workspace(_ suffix: String) -> AgentWorkspace {
    AgentWorkspace(workspaceId: "workspace-" + suffix, sessionId: "session-" + suffix,
      conversationId: "business-run-A005", taskId: "task-" + suffix, goal: "Synthetic observation",
      createdAtMillis: 1)
  }
}
