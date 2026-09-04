import XCTest
@testable import GalaxySSI

final class GlobalLongHorizonGoalStoreTests: XCTestCase {
  private var fileURL: URL!

  override func setUp() {
    super.setUp()
    fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("galaxyssi-long-horizon-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("goals.json", isDirectory: false)
  }

  override func tearDown() {
    if let fileURL {
      try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
    fileURL = nil
    super.tearDown()
  }

  func testFileStorePersistsGoalsAndStampsStatusTransitions() throws {
    let store = GlobalLongHorizonGoalStore(fileURL: fileURL)
    let source = goal(
      id: "goal-1",
      title: "Ship iOS long horizon coordinator",
      status: .active,
      createdAtMillis: 100,
      updatedAtMillis: 100
    )
    store.save([source], nowMillis: 100)

    let firstLoad = try XCTUnwrap(GlobalLongHorizonGoalStore(fileURL: fileURL).goals().first)
    XCTAssertEqual(firstLoad.status, .active)
    XCTAssertEqual(firstLoad.statusChangedAtMillis, 100)

    var completed = firstLoad
    completed.status = .completed
    completed.verificationSummary = "Verified by local regression coverage"
    completed.updatedAtMillis = 500
    store.save([completed], nowMillis: 500)

    let restored = try XCTUnwrap(GlobalLongHorizonGoalStore(fileURL: fileURL).goals().first)
    XCTAssertEqual(restored.status, .completed)
    XCTAssertEqual(restored.previousStatus, .active)
    XCTAssertEqual(restored.statusChangedAtMillis, 500)
    XCTAssertEqual(restored.verificationSummary, "Verified by local regression coverage")
  }

  func testRestoreKeepsImportedLifecycleFields() throws {
    let store = GlobalLongHorizonGoalStore(fileURL: fileURL)
    let imported = goal(
      id: "goal-import",
      title: "Imported durable goal",
      status: .blocked,
      previousStatus: .inProgress,
      statusChangedAtMillis: 900,
      blocker: "Waiting for a safe resource"
    )

    store.restore([imported])

    let restored = try XCTUnwrap(store.exportGoals().first)
    XCTAssertEqual(restored.status, .blocked)
    XCTAssertEqual(restored.previousStatus, .inProgress)
    XCTAssertEqual(restored.statusChangedAtMillis, 900)
    XCTAssertEqual(restored.blocker, "Waiting for a safe resource")
  }
}

private func goal(
  id: String,
  title: String,
  status: GlobalLongHorizonGoalStatus = .active,
  previousStatus: GlobalLongHorizonGoalStatus? = nil,
  statusChangedAtMillis: Int64 = 0,
  blocker: String = "",
  createdAtMillis: Int64 = 100,
  updatedAtMillis: Int64 = 100
) -> GlobalLongHorizonGoal {
  GlobalLongHorizonGoal(
    id: id,
    stableKey: GlobalAgentText.stableKey("store-test", title),
    topic: "GalaxySSI iOS",
    title: title,
    status: status,
    previousStatus: previousStatus,
    statusChangedAtMillis: statusChangedAtMillis,
    priority: 0.8,
    sourceConversationIds: ["conversation"],
    sourceEventIds: ["event"],
    blocker: blocker,
    createdAtMillis: createdAtMillis,
    updatedAtMillis: updatedAtMillis
  )
}
