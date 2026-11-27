import XCTest
@testable import GalaxySSI

@MainActor
final class AgentPinnedCloudTeamOfferTests: XCTestCase {
  private var validArguments: String { #"{"answer":"A complete synthetic answer.","propose_team_review":true}"# }
  private func request(_ body: String, provider: ModelStreamProvider = .openAICompatible) -> ModelStreamRequest {
    .init(requestId: "synthetic", provider: provider, endpoint: "https://fixture.invalid/v1/chat/completions", headers: [:], bodyJson: body)
  }
  private func frames() -> AgentPinnedCloudTeamOffer.Frames {
    var frames = AgentPinnedCloudTeamOffer.Frames()
    frames.observe(.init(callId: "synthetic-call", index: 0, singleNativeFunction: true))
    return frames
  }
  private func call(_ arguments: String? = nil) -> AssembledToolCall {
    .init(callId: "synthetic-call", index: 0, name: AgentPinnedCloudTeamOffer.name, argumentsJson: arguments ?? validArguments)
  }
  func testAdvertisementRequiresOpenAIAutoToolsAndPreservesOrdinaryDefinitions() throws {
    let body = #"{"tools":[{"type":"function","function":{"name":"web_search"}}],"tool_choice":"auto"}"#
    let offered = try AgentPinnedCloudTeamOffer.advertise(request(body))
    let object = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(offered.bodyJson.utf8))
    XCTAssertEqual(object["tools"]?.arrayValue?.count, 2)
    XCTAssertEqual(object["tools"]?.arrayValue?.first?.objectValue?["function"]?.objectValue?["name"], .string("web_search"))
    for source in [request(body, provider: .anthropic), request(body, provider: .gemini), request(#"{"tools":[],"tool_choice":"auto"}"#),
      request(body.replacingOccurrences(of: "auto", with: "none"))] {
      XCTAssertEqual(try AgentPinnedCloudTeamOffer.advertise(source), source)
    }
    XCTAssertEqual(try AgentPinnedCloudTeamOffer.advertise(offered), offered)
  }
  func testExactBoundedBooleanAnswerIsNotACallableAction() {
    XCTAssertEqual(AgentPinnedCloudTeamOffer.answer([call()], frames: frames(), finish: "tool_calls", hasText: false), "A complete synthetic answer.")
    for raw in [validArguments.replacingOccurrences(of: "true", with: "\"true\""), validArguments.replacingOccurrences(of: "true", with: "1"),
      validArguments.replacingOccurrences(of: "true", with: "false"), validArguments + " trailing",
      #"{"answer":"A","propose_team_review":true,"objective":"changed"}"#, #"{"answer":"","propose_team_review":true}"#] {
      XCTAssertNil(AgentPinnedCloudTeamOffer.answer([call(raw)], frames: frames(), finish: "tool_calls", hasText: false))
    }
  }
  func testOversizedNestedAndExecutableAnswersAreRejected() throws {
    for answer in [String(repeating: "x", count: 8_001), "```galaxyssi-rich", #"{"actions":[],"completion_requirements":{}}"#] {
      let raw = AgentMcpJSONCodec.stringify(["answer": .string(answer), "propose_team_review": .bool(true)])
      XCTAssertNil(AgentPinnedCloudTeamOffer.answer([call(raw)], frames: frames(), finish: "tool_calls", hasText: false))
    }
    XCTAssertNil(AgentPinnedCloudTeamOffer.answer([call(#"{"answer":{"text":"nested"},"propose_team_review":true}"#)], frames: frames(), finish: "tool_calls", hasText: false))
  }
  func testFinishTextAndMultipleCallsCannotClaimATerminalAnswer() {
    for finish in [nil, "stop", "length", "content_filter"] {
      XCTAssertNil(AgentPinnedCloudTeamOffer.answer([call()], frames: frames(), finish: finish, hasText: false))
    }
    XCTAssertNil(AgentPinnedCloudTeamOffer.answer([call()], frames: frames(), finish: "tool_calls", hasText: true))
    XCTAssertNil(AgentPinnedCloudTeamOffer.answer([call(), call()], frames: frames(), finish: "tool_calls", hasText: false))
    var ordinary = call(); ordinary.name = "web_search"
    XCTAssertNil(AgentPinnedCloudTeamOffer.answer([ordinary], frames: frames(), finish: "tool_calls", hasText: false))
  }
  func testFragmentedNativeSlotRejectsConflictingIdsIndicesAndUntypedFrames() {
    for payload in [ToolCallPayload(callId: "other", index: 0, singleNativeFunction: true),
      .init(callId: "synthetic-call", index: 1, singleNativeFunction: true), .init(callId: "synthetic-call", index: 0)] {
      var value = frames(); value.observe(payload); XCTAssertFalse(value.singleNativeSlot)
    }
    var value = frames(); value.observe(.init(callId: "", index: 0, argumentsDelta: "fragment", singleNativeFunction: true))
    XCTAssertTrue(value.singleNativeSlot); value.reject(); XCTAssertFalse(value.singleNativeSlot)
  }
  func testOnlySingleTypedChatCompletionsFramesCarryNativeAuthority() throws {
    let function: [String: Any] = ["name": AgentPinnedCloudTeamOffer.name, "arguments": validArguments]
    let call: [String: Any] = ["id": "synthetic-call", "index": 0, "type": "function", "function": function]
    func frame(_ calls: [[String: Any]], choices: Int = 1) throws -> ParsedModelStreamFrame {
      let value: [String: Any] = ["choices": Array(repeating: ["delta": ["tool_calls": calls]], count: choices)]
      let raw = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
      return ModelStreamProviderAdapters.create(provider: .openAICompatible).parse(data: raw, eventName: nil)
    }
    XCTAssertEqual(try frame([call]).toolDeltas.first?.singleNativeFunction, true)
    XCTAssertEqual(try frame([call], choices: 2).toolDeltas.first?.singleNativeFunction, false)
    XCTAssertEqual(try frame([call, call]).toolDeltas.first?.singleNativeFunction, false)
    for (key, value) in [("index", false as Any), ("index", "0"), ("type", "custom"), ("id", 123)] {
      var malformed = call; malformed[key] = value
      let decoded = try frame([malformed])
      XCTAssertFalse(decoded.toolDeltas.isEmpty)
      XCTAssertEqual(decoded.toolDeltas.first?.singleNativeFunction, false)
    }
  }
  func testCompleteJsonNativeFramesAndLegacyPayloadDecodingAreSeparated() throws {
    let json = #"{"choices":[{"message":{"tool_calls":[{"id":"synthetic-call","type":"function","function":{"name":"answer_with_optional_team_review","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}"#
    let frame = ModelStreamProviderAdapters.create(provider: .openAICompatible).parseCompleteJSON(data: json)
    XCTAssertEqual(frame.toolDeltas.first?.singleNativeFunction, true)
    let old = try JSONDecoder().decode(ToolCallPayload.self, from: Data(#"{"callId":"old","index":0}"#.utf8))
    XCTAssertFalse(old.singleNativeFunction)
    let restored = try JSONDecoder().decode(ToolCallPayload.self, from: JSONEncoder().encode(frame.toolDeltas[0]))
    XCTAssertTrue(restored.singleNativeFunction)
  }
  func testCustomResourceCeilingsAndPrivateBudgetsDeclineInvitations() {
    for profile in [AgentTaskBudgetProfile.adaptive, .fast, .economy, .custom] {
      XCTAssertTrue(AgentPinnedCloudTeamAdmission.permits(.init(profile: profile)))
      var constrained = AgentTaskBudget(profile: profile); constrained.maxOutputTokens = 123
      XCTAssertFalse(AgentPinnedCloudTeamAdmission.permits(constrained))
    }
    XCTAssertFalse(AgentPinnedCloudTeamAdmission.permits(.forProfile(.privateMode)))
    XCTAssertFalse(AgentPinnedCloudTeamAdmission.permits(.init(allowCloud: false)))
  }
  private func candidate() -> AgentLocalTeamReviewWindow.Candidate {
    var value = AgentLocalTeamReviewWindow.Candidate(owner: "synthetic-owner", conversation: "synthetic-chat",
      source: .init(message: UUID(), turn: "synthetic-turn"), objective: "Compare fare caps with service expansion and rank alternatives.",
      revision: UUID(), selection: .init(mode: .manual, targetId: "synthetic-cloud", modelId: "synthetic-model"))
    value.pin = .init(kind: .cloud, target: "synthetic-cloud", model: "synthetic-model", endpointSHA: String(repeating: "a", count: 64), host: "fixture.invalid")
    return value
  }
  func testCloudNonceIsOneShotAndCannotUseLocalAnswerDelivery() throws {
    try AgentPinnedCloudTeamDelivery.$runtime.withValue(UUID()) {
    let value = candidate(), window = AgentLocalTeamReviewWindow()
    defer { window.invalidate() }
    window.bind(value, valid: { true })
    let route = try XCTUnwrap(value.pin)
    let nonce = try XCTUnwrap(AgentLocalTeamReviewWindow.requestCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, route: route))
    XCTAssertNil(AgentLocalTeamReviewWindow.requestCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, route: route))
    XCTAssertFalse(AgentLocalTeamReviewWindow.markCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, ticket: UUID(), answer: "A"))
    XCTAssertTrue(AgentLocalTeamReviewWindow.markCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, ticket: nonce, answer: "A"))
    AgentLocalTeamReviewWindow.delivered(owner: value.owner, conversation: value.conversation, turn: value.source.turn)
    XCTAssertNil(window.proposal); XCTAssertNil(window.claim())
    }
  }
  func testEndpointPinAndOriginalObjectiveMustMatchBeforeAdmission() throws {
    try AgentPinnedCloudTeamDelivery.$runtime.withValue(UUID()) {
    let value = candidate(), window = AgentLocalTeamReviewWindow()
    defer { window.invalidate() }
    window.bind(value, valid: { true })
    let route = try XCTUnwrap(value.pin)
    let changed = AgentConversationGoal.Route(kind: .cloud, target: route.target, model: route.model,
      endpointSHA: String(repeating: "b", count: 64), host: route.host)
    XCTAssertNil(AgentLocalTeamReviewWindow.requestCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, route: changed))
    XCTAssertNil(AgentLocalTeamReviewWindow.requestCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn,
      route: route, objective: "Replaced objective"))
    }
  }
  func testCloudInvitationInvalidatesWithTheSubmittingWindow() throws {
    try AgentPinnedCloudTeamDelivery.$runtime.withValue(UUID()) {
    let value = candidate(), window = AgentLocalTeamReviewWindow()
    window.bind(value, valid: { true })
    let route = try XCTUnwrap(value.pin)
    let nonce = try XCTUnwrap(AgentLocalTeamReviewWindow.requestCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, route: route))
    window.invalidate()
    XCTAssertFalse(AgentLocalTeamReviewWindow.ownsCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, ticket: nonce, route: route))
    XCTAssertFalse(AgentLocalTeamReviewWindow.markCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, ticket: nonce, answer: "Late"))
    }
  }
  func testPinnedCloudJobsRequireOriginalTurnAndPreserveTheFlag() throws {
    let value = candidate(), route = try XCTUnwrap(value.pin)
    var job = AgentConversationalTeamJob(conversation: value.conversation, objective: value.objective, route: route)
    job.pinnedCloud = true; XCTAssertFalse(job.valid)
    job.source = value.source; XCTAssertTrue(job.valid)
    let restored = try JSONDecoder().decode(AgentConversationalTeamJob.self, from: JSONEncoder().encode(job))
    XCTAssertEqual(restored.pinnedCloud, true); XCTAssertEqual(try restored.begin().reserveCall().pinnedCloud, true)
  }
  func testSameBodyFromANewExecutionCannotUseTheEarlierReceipt() throws {
    try AgentPinnedCloudTeamDelivery.$runtime.withValue(UUID()) {
      let value = candidate(), window = AgentLocalTeamReviewWindow(), route = try XCTUnwrap(candidate().pin)
      defer { window.invalidate() }
      window.bind(value, valid: { true })
      let nonce = try XCTUnwrap(AgentLocalTeamReviewWindow.requestCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, route: route))
      XCTAssertTrue(AgentLocalTeamReviewWindow.markCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, ticket: nonce, answer: "Same body"))
      AgentPinnedCloudTeamDelivery.$runtime.withValue(UUID()) {
        XCTAssertFalse(AgentLocalTeamReviewWindow.ownsCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, ticket: nonce, route: route))
        XCTAssertNil(AgentLocalTeamReviewWindow.requestCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, route: route))
      }
      XCTAssertFalse(AgentLocalTeamReviewWindow.markCloud(owner: value.owner, conversation: value.conversation, turn: value.source.turn, ticket: nonce, answer: "Same body"))
      XCTAssertNil(window.proposal)
    }
  }
}
