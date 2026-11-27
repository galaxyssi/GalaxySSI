import XCTest
@testable import GalaxySSI

final class AgentConversationalTeamJobTests: XCTestCase {
  private func job() -> AgentConversationalTeamJob {
    .init(conversation: "synthetic-chat", objective: "Compare two fictional proposals.",
      route: .init(kind: .local, target: "local-llm", model: "synthetic-profile", endpointSHA: "", host: ""))
  }
  func testOnlyAQueuedJobCanBeginAndOnlyRunningJobsConsumeCalls() throws {
    let queued = job()
    XCTAssertTrue(queued.valid); XCTAssertTrue(queued.active)
    XCTAssertThrowsError(try queued.reserveCall())
    let running = try queued.begin()
    XCTAssertEqual(running.state, .running); XCTAssertEqual(running.calls, 0)
    XCTAssertThrowsError(try running.begin())
  }
  func testTwelveCallLimitCannotBeExtended() throws {
    var value = try job().begin()
    for i in 1...12 { value = try value.reserveCall(); XCTAssertEqual(value.calls, i) }
    XCTAssertThrowsError(try value.reserveCall())
    XCTAssertEqual(value.route, job().route)
    XCTAssertEqual(value.objective, job().objective)
  }
  func testFinishedAndStoppedJobsCannotDispatchOrCompleteAgain() throws {
    let running = try job().begin().reserveCall()
    let finished = try running.finish("A public result.")
    let stopped = try running.stop()
    XCTAssertFalse(finished.active); XCTAssertFalse(stopped.active)
    XCTAssertThrowsError(try finished.reserveCall()); XCTAssertThrowsError(try stopped.reserveCall())
    XCTAssertThrowsError(try finished.finish("Late result.")); XCTAssertThrowsError(try stopped.finish("Late result."))
  }
  func testAnswerMustBeCompleteBoundedAndNonExecutable() throws {
    let value = try job().begin()
    for answer in [" ", String(repeating: "x", count: 64_001), "```galaxyssi-rich"] {
      XCTAssertThrowsError(try value.finish(answer))
    }
  }
  func testCheckpointRoundTripPreservesUncertainRunningState() throws {
    let value = try job().begin().reserveCall()
    let decoded = try JSONDecoder().decode(AgentConversationalTeamJob.self, from: JSONEncoder().encode(value))
    XCTAssertEqual(decoded, value); XCTAssertEqual(decoded.state, .running)
    XCTAssertThrowsError(try decoded.begin())
    XCTAssertEqual(try decoded.finish("Interrupted; no automatic replay.").state, .finished)
  }
}
