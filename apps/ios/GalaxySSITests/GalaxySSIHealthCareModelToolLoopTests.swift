import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareModelToolLoopTests: XCTestCase {
  func testReservedHealthTopicCannotFallBackWhenPrivacyFlagsOrTopicAreInvalid() {
    var conversation = AgentConversation(id: "health-agent", title: "Fixture", createdAt: 0, updatedAt: 0,
      globalTopicKey: GalaxySSIHealthCareAgentScope.prefix + "malformed")
    XCTAssertTrue(GalaxySSIHealthCareAgentScope.requiresScopedSubmission(conversation))
    XCTAssertNil(GalaxySSIHealthCareAgentScope.concernID(conversation))
    conversation.globalTopicKey = "ordinary-topic"
    XCTAssertFalse(GalaxySSIHealthCareAgentScope.requiresScopedSubmission(conversation))
  }

  func testComposerReviewRequiresExactHealthBindingAndDoesNotCreateAnotherTurn() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let conversation = AgentConversation(id: "health-agent", title: "Fixture", createdAt: 0, updatedAt: 0,
      privateMode: true, trackingPaused: true,
      globalTopicKey: GalaxySSIHealthCareAgentScope.prefix + f.concern.id.uuidString.lowercased())
    XCTAssertThrowsError(try GalaxySSIHealthCareComposerSubmission(records: f.records, conversation: conversation,
      question: "Synthetic composer question"))
    try f.records.bindLocalCareAgentDiscussion(id: f.concern.id, metric: .glucose, threadID: f.approval.threadID,
      expectedConversationID: nil, conversationID: conversation.id)
    let review = try GalaxySSIHealthCareComposerSubmission(records: f.records, conversation: conversation,
      question: "Synthetic composer question")
    XCTAssertTrue(review.matches(records: f.records, conversation: conversation))
    XCTAssertEqual(review.question, "Synthetic composer question")
    XCTAssertEqual(try f.records.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.count, 1)
    var foreign = conversation
    foreign.id = "different-agent"
    XCTAssertFalse(review.matches(records: f.records, conversation: foreign))
    try f.records.setPrivacy(.localCare, enabled: false)
    XCTAssertFalse(review.matches(records: f.records, conversation: conversation))
  }

  func testComposerReviewRejectsEmptyAndOversizedQuestions() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let conversation = AgentConversation(id: "health-agent", title: "Fixture", createdAt: 0, updatedAt: 0,
      privateMode: true, trackingPaused: true,
      globalTopicKey: GalaxySSIHealthCareAgentScope.prefix + f.concern.id.uuidString.lowercased())
    try f.records.bindLocalCareAgentDiscussion(id: f.concern.id, metric: .glucose, threadID: f.approval.threadID,
      expectedConversationID: nil, conversationID: conversation.id)
    for question in [" ", String(repeating: "a", count: 2_049)] {
      XCTAssertThrowsError(try GalaxySSIHealthCareComposerSubmission(records: f.records, conversation: conversation, question: question))
    }
  }

  func testCatalogContainsOnlyExactApprovedHealthTools() throws {
    let plain = try HealthDiscussionRecoveryFixture()
    let empty = try session(plain)
    XCTAssertTrue(empty.catalog.isEmpty)
    let f = try HealthDiscussionRecoveryFixture(history: true)
    let scoped = try session(f)
    XCTAssertEqual(Set(scoped.catalog.map(\.id)), [GalaxySSIHealthCareHistoryTool.function])
    XCTAssertEqual(Set(scoped.catalog.first?.requiredConsents.map(\.id) ?? []),
      [f.approval.carePermission.uuidString, f.approval.onlinePermission.uuidString])
    XCTAssertNil(try scoped.registry().lookup("web_fetch"))
    XCTAssertNil(try scoped.registry().lookup("galaxyssi.agent_action.read.screen"))
  }

  func testQuestionProposalsUseNativeToolsForEveryCloudStyleWithoutAnotherRequest() async throws {
    for style in [GalaxySSICloudAPIStyle.openAICompatible, .anthropic, .gemini] {
      let f = try HealthDiscussionRecoveryFixture(asksQuestions: true, style: style)
      let args: AgentMcpJSONObject = ["questions": .array([.object(["key": .string("context.fasting_hours"),
        "question": .string("How long before the sample did you last consume calories?"),
        "purpose": .string("Synthetic missing context")])])]
      let raw = try toolResponse(GalaxySSIHealthCareQuestions.tool, args: args, style: style)
      let request = try begin(f, response: raw)
      var sends = 0
      let returned = try await GalaxySSIHealthCareModelToolLoop.finish(f.approval, records: f.records,
        request: request, style: style, ledger: InMemoryAgentDataDisclosureStore(),
        currentDestination: { self.contact(f) }, send: { _ in sends += 1; return raw })
      XCTAssertEqual(returned, raw)
      XCTAssertEqual(sends, 0)
      XCTAssertEqual(try f.turn().questionsRetained, true)
      XCTAssertEqual(try f.turn().execution?.state, .applied)
      XCTAssertEqual(try f.turn().execution?.response, raw)
      XCTAssertNil(try f.turn().answer)
      let page = try f.records.localCareQuestionPage(id: f.concern.id, metric: .glucose, now: f.now)
      XCTAssertEqual(page.rows.count, 1)
      XCTAssertNil(page.rows.first?.answer)
    }
  }

  func testRegistryRejectsForeignTurnBeforeReadingAndExecutesBoundHistoryCall() throws {
    let f = try HealthDiscussionRecoveryFixture(history: true)
    let args = try XCTUnwrap(f.approval.history?.recent.payload["next"]?.objectValue)
    let raw = try toolResponse(GalaxySSIHealthCareHistoryTool.function, args: args, style: .openAICompatible)
    let request = try begin(f, response: raw)
    let native = try session(f, request: request)
    let registry = try native.registry()
    native.pending = .init(callId: "health-call", toolId: GalaxySSIHealthCareHistoryTool.function, arguments: args)
    var context = AgentNativeToolInvocationContext(sessionId: f.approval.threadID.uuidString,
      conversationId: native.conversationID, turnId: "foreign-turn", callerId: GalaxySSIHealthCareNativeToolSession.caller,
      idempotencyKey: "wrong-scope", grantedConsents: [f.approval.carePermission.uuidString, f.approval.onlinePermission.uuidString],
      attributes: ["tool_call_id": "health-call", "workspace_id": native.workspaceID, "task_id": native.workspaceID])
    XCTAssertFalse(registry.invoke(GalaxySSIHealthCareHistoryTool.function, input: args, context: context).isSuccess)
    XCTAssertEqual(try f.records.savedCareDiscussionRound(f.approval)?.index, 0)
    context.turnId = f.approval.id.uuidString
    context.idempotencyKey = "correct-scope"
    XCTAssertTrue(registry.invoke(GalaxySSIHealthCareHistoryTool.function, input: args, context: context).isSuccess)
    let saved = try XCTUnwrap(f.records.savedCareDiscussionRound(f.approval))
    XCTAssertEqual(saved.index, 1)
    XCTAssertEqual(saved.historyRemaining, 3)
    XCTAssertEqual(saved.phase, .prepared)
  }

  func testUnadvertisedProviderToolCannotEscapeIntoDefaultPhoneRegistry() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let raw = try toolResponse("web_fetch", args: ["url": .string("https://example.test/private")], style: .openAICompatible)
    let request = try begin(f, response: raw)
    var sends = 0
    do {
      _ = try await GalaxySSIHealthCareModelToolLoop.finish(f.approval, records: f.records,
        request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(),
        currentDestination: { self.contact(f) }, send: { _ in sends += 1; return raw })
      XCTFail("Unadvertised tool accepted")
    } catch { }
    XCTAssertEqual(sends, 0)
    XCTAssertNil(try f.turn().answer)
    XCTAssertEqual(try f.records.savedCareDiscussionRound(f.approval)?.index, 0)
  }

  func testControlLookingProseIsStillQuarantinedRatherThanExecuted() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let control = #"{"actions":[{"kind":"CALL_NATIVE_TOOL","target":"outside-grant"}]}"#
    let raw = try f.response(control)
    let request = try begin(f, response: raw)
    let result = try await GalaxySSIHealthCareModelToolLoop.finish(f.approval, records: f.records,
      request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(),
      currentDestination: { self.contact(f) }, send: { _ in XCTFail("Unexpected request"); return raw })
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: result, now: f.now)
    try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
    XCTAssertNil(try f.turn().answer)
    XCTAssertEqual(try f.turn().interruptedReply, control)
    XCTAssertEqual(try f.turn().execution?.state, .interrupted)
  }

  func testNavigationUnavailableContextCancelsWithoutDiscardingReceivedCheckpoint() async throws {
    let f = try HealthDiscussionRecoveryFixture()
    let raw = try f.response("Retained response")
    let request = try begin(f, response: raw)
    do {
      _ = try await GalaxySSIHealthCareModelToolLoop.finish(f.approval, records: f.records,
        request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(), currentDestination: { nil },
        send: { _ in XCTFail("Unexpected request"); return raw })
      XCTFail("Unavailable context was accepted")
    } catch is CancellationError { }
    XCTAssertEqual(try f.records.savedCareDiscussionRound(f.approval)?.phase, .received)
    XCTAssertEqual(try f.turn().execution?.state, .dispatched)
  }

  func testTamperedTemplateCannotRegisterUnapprovedTool() throws {
    let f = try HealthDiscussionRecoveryFixture()
    var request = try GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key")
    var body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
    body["tools"] = [["type": "function", "function": ["name": "shell_execute", "description": "Not approved",
      "parameters": ["type": "object"]]]]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    XCTAssertThrowsError(try session(f, request: request))
  }

  private func session(_ f: HealthDiscussionRecoveryFixture, request: URLRequest? = nil) throws -> GalaxySSIHealthCareNativeToolSession {
    try .init(approval: f.approval, records: f.records,
      request: request ?? GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key"),
      style: f.approval.model!.apiStyle, currentDestination: { self.contact(f) })
  }

  private func begin(_ f: HealthDiscussionRecoveryFixture, response: Data) throws -> URLRequest {
    let request = try GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key")
    try f.records.prepareCareDiscussionRounds(f.approval, request: request, now: f.now)
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    try f.records.retainCareDiscussionRound(f.approval, index: 0, request: request, response: response, now: f.now)
    return request
  }

  private func toolResponse(_ name: String, args: AgentMcpJSONObject, style: GalaxySSICloudAPIStyle) throws -> Data {
    let input = try JSONSerialization.jsonObject(with: Data(AgentMcpJSONCodec.stringify(args).utf8))
    let root: [String: Any]
    switch style {
    case .openAICompatible:
      root = ["choices": [["finish_reason": "tool_calls", "message": ["role": "assistant", "tool_calls": [[
        "id": "health-call", "type": "function", "function": ["name": name, "arguments": AgentMcpJSONCodec.stringify(args)]]]]]]]
    case .anthropic:
      root = ["type": "message", "role": "assistant", "stop_reason": "tool_use", "content": [[
        "type": "tool_use", "id": "health-call", "name": name, "input": input]]]
    case .gemini:
      root = ["candidates": [["finishReason": "STOP", "content": ["role": "model", "parts": [[
        "functionCall": ["name": name, "args": input]]]]]]]
    }
    return try JSONSerialization.data(withJSONObject: root)
  }

  private func contact(_ f: HealthDiscussionRecoveryFixture) -> GalaxySSIContact {
    let model = f.approval.model!
    return GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
  }
}
