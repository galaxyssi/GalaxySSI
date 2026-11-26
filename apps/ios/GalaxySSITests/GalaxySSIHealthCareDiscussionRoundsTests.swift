import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareDiscussionRoundsTests: XCTestCase {
  func testReceivedRoundReopensWithExactBytesAndWithoutPersistedHeaders() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let request = try template(f)
    try f.records.prepareCareDiscussionRounds(f.approval, request: request, now: f.now)
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    let reply = try f.response("Saved round reply")
    try f.records.retainCareDiscussionRound(f.approval, index: 0, request: request, response: reply, now: f.now)
    try f.records.retainCareDiscussionRound(f.approval, index: 0, request: request, response: reply, now: f.now)
    XCTAssertThrowsError(try f.records.retainCareDiscussionRound(f.approval, index: 0,
      request: request, response: f.response("Different receipt"), now: f.now))
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    let saved = try XCTUnwrap(reopened.savedCareDiscussionRound(f.approval, now: f.now))
    XCTAssertEqual(saved.response, reply)
    XCTAssertEqual(saved.requestBody, request.httpBody)
    XCTAssertEqual(saved.phase, .received)
    let encoded = try JSONEncoder().encode(saved)
    XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("fixture-api-key"))
    XCTAssertNil(try Data(contentsOf: f.file).range(of: reply))
    var sends = 0
    let result = try await GalaxySSIHealthScopedReadTransport.resume(f.approval, records: reopened,
      request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(),
      currentDestination: { self.contact(f) }, send: { _ in sends += 1; return reply })
    XCTAssertEqual(result, reply)
    XCTAssertEqual(sends, 0)
    try reopened.retainLocalCareDiscussionResponse(f.approval, response: result, now: f.now)
    try reopened.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
    XCTAssertEqual(try f.turn().answer, "Saved round reply")
  }

  func testDefinitelyUnsentInitialRequestCanResumeExactlyOnce() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let request = try template(f)
    try f.records.prepareCareDiscussionRounds(f.approval, request: request, now: f.now)
    var sends = 0
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    do {
      try await runtime.restore(f.approval, mayApply: { true }, resumeRound: { throw CancellationError() })
      XCTFail("Cancelled recovery was reported complete")
    } catch { }
    XCTAssertEqual(try f.records.savedCareDiscussionRound(f.approval)?.phase, .prepared)
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .paused)
    try await runtime.restore(f.approval, mayApply: { true }, resumeRound: {
      let result = try await GalaxySSIHealthScopedReadTransport.resume(f.approval, records: f.records,
        request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(),
        currentDestination: { self.contact(f) }, send: { wire in
          sends += 1
          XCTAssertEqual(wire.httpBody, request.httpBody)
          XCTAssertEqual(try f.records.savedCareDiscussionRound(f.approval)?.phase, .dispatched)
          return try f.response("Initial recovery reply")
        })
      try f.records.retainLocalCareDiscussionResponse(f.approval, response: result, now: f.now)
      try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
    })
    XCTAssertEqual(sends, 1)
    XCTAssertEqual(try f.turn().execution?.state, .applied)
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .completed)
  }

  func testReceivedHistoryCallResumesWithOnlyTheNewContinuationRequest() async throws {
    let f = try HealthDiscussionRecoveryFixture(history: true)
    let request = try template(f)
    try beginReceivedHistoryRound(f, request: request)
    var sends = 0
    let result = try await GalaxySSIHealthScopedReadTransport.resume(f.approval, records: f.records,
      request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(),
      currentDestination: { self.contact(f) }, send: { wire in
        sends += 1
        XCTAssertNotEqual(wire.httpBody, request.httpBody)
        XCTAssertEqual(wire.value(forHTTPHeaderField: "Authorization"), request.value(forHTTPHeaderField: "Authorization"))
        let saved = try XCTUnwrap(f.records.savedCareDiscussionRound(f.approval))
        XCTAssertEqual(saved.index, 1)
        XCTAssertEqual(saved.phase, .dispatched)
        XCTAssertEqual(saved.historyRemaining, 3)
        XCTAssertEqual(saved.requestBody, wire.httpBody)
        return try f.response("History-based synthetic reply")
      })
    XCTAssertEqual(sends, 1)
    XCTAssertEqual(try f.records.savedCareDiscussionRound(f.approval)?.phase, .received)
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: result, now: f.now)
    try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
  }

  func testPreparedContinuationPreservesOpaqueCursorAndRemainingBudget() async throws {
    let f = try HealthDiscussionRecoveryFixture(history: true)
    let request = try template(f)
    try beginReceivedHistoryRound(f, request: request)
    let saved = try XCTUnwrap(f.records.savedCareDiscussionRound(f.approval, now: f.now))
    let (next, wire) = try preparedHistoryContinuation(f, request: request, saved: saved)
    try f.records.prepareNextCareDiscussionRound(f.approval, expected: saved, next: next, now: f.now)
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    XCTAssertEqual(try reopened.savedCareDiscussionRound(f.approval, now: f.now), next)
    var sends = 0
    _ = try await GalaxySSIHealthScopedReadTransport.resume(f.approval, records: reopened,
      request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(),
      currentDestination: { self.contact(f) }, send: { actual in
        sends += 1
        XCTAssertEqual(actual.httpBody, wire.httpBody)
        XCTAssertEqual(try reopened.savedCareDiscussionRound(f.approval)?.history, next.history)
        return try f.response("Prepared continuation reply")
      })
    XCTAssertEqual(sends, 1)
    XCTAssertEqual(try reopened.savedCareDiscussionRound(f.approval)?.historyRemaining, 3)
  }

  func testDispatchedRoundWithoutReceiptCannotBeReplayed() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let request = try template(f)
    try f.records.prepareCareDiscussionRounds(f.approval, request: request, now: f.now)
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    XCTAssertFalse(try XCTUnwrap(f.records.savedCareDiscussionRound(f.approval)).canResume)
    var sends = 0
    do {
      _ = try await GalaxySSIHealthScopedReadTransport.resume(f.approval, records: f.records,
        request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(),
        currentDestination: { self.contact(f) }, send: { _ in sends += 1; return try f.response("Must not send") })
      XCTFail("Uncertain dispatch was replayed")
    } catch { }
    let runtime = GalaxySSIHealthCareTaskRuntime.shared(records: f.records)
    try await runtime.restore(f.approval, mayApply: { true }, resumeRound: { sends += 1 })
    XCTAssertEqual(sends, 0)
    XCTAssertEqual(try f.turn().execution?.state, .interrupted)
    XCTAssertEqual(runtime.persistedWorkspace(f.approval)?.status, .blocked)
  }

  func testRoundFencesExpiryRevocationWrongEndpointAndStaleBudgetSnapshots() throws {
    let f = try HealthDiscussionRecoveryFixture(history: true)
    let request = try template(f)
    try beginReceivedHistoryRound(f, request: request)
    let saved = try XCTUnwrap(f.records.savedCareDiscussionRound(f.approval, now: f.now))
    var (next, _) = try preparedHistoryContinuation(f, request: request, saved: saved)
    next.historyRemaining = saved.historyRemaining
    XCTAssertThrowsError(try f.records.prepareNextCareDiscussionRound(f.approval, expected: saved, next: next, now: f.now))
    var wrong = request; wrong.url = URL(string: "https://other.example.test/v1/chat/completions")
    XCTAssertThrowsError(try f.records.retainCareDiscussionRound(f.approval, index: 0,
      request: wrong, response: f.response("Wrong route"), now: f.now))
    XCTAssertThrowsError(try f.records.savedCareDiscussionRound(f.approval,
      now: f.now.addingTimeInterval(GalaxySSIHealthCareDiscussion.approvalLifetime + 1)))
    try f.records.setHealthOnlinePermission(false)
    XCTAssertThrowsError(try f.records.savedCareDiscussionRound(f.approval, now: f.now))
  }

  func testReceivedDisclosureIsNotRelabeledFailedWhenLocalReceiptWriteIsRejected() async throws {
    let f = try HealthDiscussionRecoveryFixture(history: true)
    let request = try template(f)
    try beginReceivedHistoryRound(f, request: request)
    let ledger = InMemoryAgentDataDisclosureStore()
    do {
      _ = try await GalaxySSIHealthScopedReadTransport.resume(f.approval, records: f.records,
        request: request, style: .openAICompatible, ledger: ledger, currentDestination: { self.contact(f) }, send: { _ in
          try f.records.setHealthOnlinePermission(false)
          return try f.response("Received after scope revocation")
        })
      XCTFail("Revoked response entered the discussion")
    } catch { }
    XCTAssertEqual(ledger.list().last?.status, .sent)
    XCTAssertNil(try f.turn().answer)
  }

  func testBlockedDestinationCannotDispatchAPreparedRound() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let request = try template(f)
    try f.records.prepareCareDiscussionRounds(f.approval, request: request, now: f.now)
    var sends = 0
    do {
      _ = try await GalaxySSIHealthScopedReadTransport.resume(f.approval, records: f.records,
        request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(), currentDestination: { nil },
        send: { _ in sends += 1; return try f.response("Not authorized") })
      XCTFail("Missing current destination was accepted")
    } catch { }
    XCTAssertEqual(sends, 0)
    XCTAssertEqual(try f.records.savedCareDiscussionRound(f.approval)?.phase, .prepared)
  }

  private func template(_ f: HealthDiscussionRecoveryFixture) throws -> URLRequest {
    try GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key")
  }

  private func beginReceivedHistoryRound(_ f: HealthDiscussionRecoveryFixture, request: URLRequest) throws {
    try f.records.prepareCareDiscussionRounds(f.approval, request: request, now: f.now)
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    let history = try XCTUnwrap(f.approval.history)
    let arguments = try XCTUnwrap(history.recent.payload["next"]?.objectValue)
    let response: AgentMcpJSONObject = ["choices": .array([.object(["finish_reason": .string("tool_calls"),
      "message": .object(["role": .string("assistant"), "tool_calls": .array([.object([
        "id": .string("saved-history-call"), "type": .string("function"), "function": .object([
          "name": .string(GalaxySSIHealthCareHistoryTool.function), "arguments": .string(AgentMcpJSONCodec.stringify(arguments))])])])])])])]
    try f.records.retainCareDiscussionRound(f.approval, index: 0, request: request,
      response: Data(AgentMcpJSONCodec.stringify(response).utf8), now: f.now)
  }

  private func preparedHistoryContinuation(_ f: HealthDiscussionRecoveryFixture, request: URLRequest,
      saved: GalaxySSIHealthCareDiscussionRounds.State) throws -> (GalaxySSIHealthCareDiscussionRounds.State, URLRequest) {
    let call = try XCTUnwrap(GalaxySSIHealthCareHistoryTool.call(XCTUnwrap(saved.response), style: .openAICompatible, proposesPlan: false))
    let cursor = try XCTUnwrap(saved.history?.cursor)
    let page = try f.records.readLocalCareDiscussionHistory(f.approval, after: cursor, now: f.now)
    let output = try GalaxySSIHealthCareHistoryTool.output(page, metric: .glucose, turn: f.approval.id, remaining: 3)
    let wire = try GalaxySSIHealthCareHistoryTool.continuing(request, with: call, output: output,
      style: .openAICompatible, proposesPlan: false, historyAvailable: output.cursor != nil)
    var next = saved
    next.index = 1; next.phase = .prepared; next.response = nil
    next.requestBody = try XCTUnwrap(wire.httpBody)
    next.history = output; next.historyRemaining = 3
    return (next, wire)
  }

  private func contact(_ f: HealthDiscussionRecoveryFixture) -> GalaxySSIContact {
    let model = f.approval.model!
    return GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
  }
}
