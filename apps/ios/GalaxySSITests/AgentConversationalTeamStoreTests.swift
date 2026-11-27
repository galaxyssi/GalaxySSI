import XCTest
@testable import GalaxySSI

final class AgentConversationalTeamStoreTests: XCTestCase {
  private func fixture(_ body: (AgentConversationalTeamStore, UserDefaults, InMemorySecretStore) throws -> Void) throws {
    let suite = "team-synthetic-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    try body(.init(owner: "synthetic-owner", defaults: defaults, secrets: secrets), defaults, secrets)
  }
  private func job() -> AgentConversationalTeamJob {
    .init(conversation: "synthetic-chat", objective: "Compare fictional route designs",
      route: .init(kind: .local, target: "local-llm", model: "synthetic-model", endpointSHA: "", host: "",
        artifactSHA: String(repeating: "a", count: 64)))
  }
  func testClaimIsDurableAndRecoveredRunningCannotRestart() throws {
    try fixture { store, defaults, secrets in
      let queued = job(), running = try queued.begin()
      try store.replace(queued, expected: nil); try store.replace(running, expected: queued)
      let reopened = AgentConversationalTeamStore(owner: "synthetic-owner", defaults: defaults, secrets: secrets)
      XCTAssertEqual(try reopened.read(queued.conversation), running)
      XCTAssertThrowsError(try running.begin())
      XCTAssertThrowsError(try reopened.replace(running, expected: queued))
      let interrupted = try running.finish("Synthetic interruption receipt")
      try reopened.replace(interrupted, expected: running)
      XCTAssertEqual(try reopened.read(queued.conversation), interrupted)
    }
  }
  func testSiblingCallReservationsAreSerializedAndBounded() throws {
    try fixture { store, _, _ in
      let queued = job(); try store.replace(queued, expected: nil)
      var current = try queued.begin(); try store.replace(current, expected: queued)
      for _ in 0..<12 {
        let next = try current.reserveCall()
        try store.replace(next, expected: current)
        XCTAssertThrowsError(try store.replace(next, expected: current))
        current = try XCTUnwrap(store.read(queued.conversation))
      }
      XCTAssertEqual(current.calls, 12); XCTAssertThrowsError(try current.reserveCall())
    }
  }
  func testStopRejectsLateCompletionAndNewRunCannotOverwriteActiveRun() throws {
    try fixture { store, _, _ in
      let queued = job(); try store.replace(queued, expected: nil)
      let running = try queued.begin(); try store.replace(running, expected: queued)
      XCTAssertThrowsError(try store.replace(job(), expected: running))
      let stopped = try running.stop(); try store.replace(stopped, expected: running)
      XCTAssertThrowsError(try store.replace(running.finish("Late synthetic result"), expected: running))
      try store.retire(stopped)
      XCTAssertNil(try store.read(queued.conversation))
      try store.replace(job(), expected: nil)
    }
  }
  func testConversationDeletionTombstonePreventsResurrection() throws {
    try fixture { store, _, _ in
      let queued = job(); try store.replace(queued, expected: nil)
      store.remove(queued.conversation)
      XCTAssertThrowsError(try store.read(queued.conversation))
      XCTAssertThrowsError(try store.replace(queued, expected: nil))
      XCTAssertTrue(try store.jobs().isEmpty)
    }
  }
  func testOwnerIsolationEncryptionAndMissingKeyFailClosed() throws {
    try fixture { store, defaults, secrets in
      let queued = job(); try store.replace(queued, expected: nil)
      let other = AgentConversationalTeamStore(owner: "other-owner", defaults: defaults, secrets: secrets)
      XCTAssertNil(try other.read(queued.conversation))
      let lost = AgentConversationalTeamStore(owner: "synthetic-owner", defaults: defaults, secrets: InMemorySecretStore())
      XCTAssertThrowsError(try lost.read(queued.conversation))
      for value in defaults.dictionaryRepresentation().values {
        if let data = value as? Data { XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(queued.objective)) }
        if let text = value as? String { XCTAssertFalse(text.contains(queued.objective)) }
      }
    }
  }
  func testOnlyTerminalRowsRetireAndPrivateResetRemovesJobs() throws {
    try fixture { store, defaults, secrets in
      let queued = job(); try store.replace(queued, expected: nil)
      XCTAssertThrowsError(try store.retire(queued))
      AgentConversationalTeamStore.destroyAll(defaults: defaults, secrets: secrets)
      XCTAssertNil(try store.read(queued.conversation)); XCTAssertTrue(try store.jobs().isEmpty)
    }
  }
}
