import XCTest
@testable import GalaxySSI

@MainActor
final class AgentLocalTeamReviewTests: XCTestCase {
  private let answer = #"{"answer":"Expand service under these assumptions.","tool_calls":[],"propose_team_review":true}"#
  private var inference: LocalModelInferenceResult {
    .init(text: "", profileId: "synthetic", backend: "test", smeAvailable: false, elapsedMillis: 1)
  }
  private func candidate(_ selection: AgentModelSelection = .init()) -> AgentLocalTeamReviewWindow.Candidate {
    .init(owner: "synthetic-owner", conversation: "synthetic-chat", source: .init(message: UUID(), turn: "synthetic-turn"),
      objective: "Compare fare caps with service expansion, including ranking reversals.", revision: UUID(), selection: selection)
  }
  private func request(_ candidate: AgentLocalTeamReviewWindow.Candidate, profile: String = "synthetic") -> Bool {
    AgentLocalTeamReviewWindow.request(owner: candidate.owner, conversation: candidate.conversation,
      turn: candidate.source.turn, objective: candidate.objective, profile: profile)
  }
  func testOptionalFlagPreservesNormalAnswerWithoutAnExtraCall() throws {
    let proposed = try AgentIOSLocalModelWebToolProtocol.decode(answer, inference: inference, offerTeamReview: true)
    let ordinary = try AgentIOSLocalModelWebToolProtocol.decode(answer, inference: inference)
    XCTAssertEqual(proposed.assistantText, ordinary.assistantText)
    XCTAssertEqual(proposed.providerMetadata[AgentLocalTeamReviewProposal.field], .bool(true))
    XCTAssertNil(ordinary.providerMetadata[AgentLocalTeamReviewProposal.field])
    XCTAssertTrue(proposed.toolCalls.isEmpty)
    XCTAssertFalse(AgentIOSLocalModelWebToolProtocol.systemPrompt(catalog: [], basePrompt: "").contains(AgentLocalTeamReviewProposal.field))
    XCTAssertTrue(AgentIOSLocalModelWebToolProtocol.systemPrompt(catalog: [], basePrompt: "", offerTeamReview: true).contains(AgentLocalTeamReviewProposal.field))
  }
  func testQuotedFencedPartialAndExtendedObjectsCannotProposeOrSmuggleTools() throws {
    let mixed = answer.replacingOccurrences(of: "[]", with: #"[{"name":"synthetic.write","arguments":{}}]"#)
    for raw in [mixed, "Example: " + answer, answer + " trailing", "```json\n" + answer + "\n```", "x</think>" + answer,
      answer.replacingOccurrences(of: "true", with: "\"true\""),
      answer.replacingOccurrences(of: "{\"answer\"", with: "{\"objective\":\"changed\",\"answer\"")] {
      let response = try AgentIOSLocalModelWebToolProtocol.decode(raw, inference: inference, offerTeamReview: true)
      XCTAssertNil(response.providerMetadata[AgentLocalTeamReviewProposal.field])
      XCTAssertTrue(response.toolCalls.isEmpty)
    }
  }
  func testOrdinaryToolDecisionIsUnchangedAndClosedThinkingPrefixIsAllowed() throws {
    let raw = #"{"answer":"","tool_calls":[{"name":"synthetic.read","arguments":{}}]}"#
    XCTAssertEqual(try AgentIOSLocalModelWebToolProtocol.decode(raw, inference: inference, offerTeamReview: true).toolCalls.first?.toolId, "synthetic.read")
    XCTAssertTrue(AgentLocalTeamReviewProposal.proposed(AgentLocalTeamReviewProposal.envelope("<think>private</think>" + answer)))
    XCTAssertNil(AgentLocalTeamReviewProposal.envelope("<think>unfinished" + answer))
  }
  func testPlannerProposalHasOnlyRespondTextAndBooleanFlag() {
    let raw = #"{"disposition":"respond","final_response":"Normal answer","propose_team_review":true}"#
    XCTAssertTrue(AgentLocalTeamReviewProposal.proposed(AgentLocalTeamReviewProposal.envelope(raw), planner: true))
    for changed in [raw.replacingOccurrences(of: "true", with: "1"), raw + "{}",
      raw.replacingOccurrences(of: "respond", with: "execute"),
      raw.replacingOccurrences(of: "{", with: "{\"actions\":[],")] {
      XCTAssertFalse(AgentLocalTeamReviewProposal.proposed(AgentLocalTeamReviewProposal.envelope(changed), planner: true))
    }
  }
  func testPrivacySoloAndCommandExclusionsDoNotDependOnTheModel() {
    let objective = candidate().objective
    XCTAssertNil(AgentConversationalTeamCommand.parse(objective))
    XCTAssertTrue(AgentConversationalTeamCommand.allowsModelReview(objective, language: "en"))
    for excluded in ["Compare my medical records.", "Don't use a team. " + objective, "/goal " + objective, String(repeating: "x", count: 4_001)] {
      XCTAssertFalse(AgentConversationalTeamCommand.allowsModelReview(excluded, language: "en"))
    }
  }
  func testWindowOwnsOneShotProposalAndDoesNotOpenBeforeAnswerDelivery() throws {
    let window = AgentLocalTeamReviewWindow(), value = candidate()
    defer { window.invalidate() }
    window.bind(value, valid: { true })
    XCTAssertTrue(request(value)); XCTAssertFalse(request(value))
    AgentLocalTeamReviewWindow.mark(owner: value.owner, conversation: value.conversation, turn: value.source.turn)
    XCTAssertNil(window.proposal)
    AgentLocalTeamReviewWindow.delivered(owner: value.owner, conversation: "other", turn: value.source.turn)
    XCTAssertNil(window.proposal)
    AgentLocalTeamReviewWindow.delivered(owner: value.owner, conversation: value.conversation, turn: value.source.turn)
    XCTAssertEqual(window.claim(), value); XCTAssertNil(window.claim())
  }
  func testDraftLifecycleAndOwnerChangesInvalidatePendingSuggestion() {
    let window = AgentLocalTeamReviewWindow(), value = candidate()
    var valid = true
    window.bind(value, valid: { valid }); XCTAssertTrue(request(value))
    valid = false
    AgentLocalTeamReviewWindow.mark(owner: value.owner, conversation: value.conversation, turn: value.source.turn)
    AgentLocalTeamReviewWindow.delivered(owner: value.owner, conversation: value.conversation, turn: value.source.turn)
    XCTAssertNil(window.claim())
    valid = true; window.bind(value, valid: { valid }); window.invalidate()
    XCTAssertFalse(request(value)); XCTAssertNil(window.proposal)
  }
  func testManualCloudOrOtherLocalProfileCannotOfferAnOnDeviceSuggestion() {
    let window = AgentLocalTeamReviewWindow()
    defer { window.invalidate() }
    let cloud = candidate(.init(mode: .manual, targetId: "cloud", modelId: "cloud-model"))
    window.bind(cloud, valid: { true }); XCTAssertFalse(request(cloud))
    let local = candidate(.init(mode: .manual, targetId: "local-llm", modelId: "synthetic"))
    window.bind(local, valid: { true }); XCTAssertFalse(request(local, profile: "different")); XCTAssertTrue(request(local))
  }
  func testLegacyJobsDecodeWithoutSourceAndModelReviewJobsPreserveOriginalTurn() throws {
    let value = candidate()
    var job = AgentConversationalTeamJob(conversation: value.conversation, objective: value.objective,
      route: .init(kind: .local, target: "local-llm", model: "synthetic", endpointSHA: "", host: "",
        artifactSHA: String(repeating: "a", count: 64)))
    let old = try JSONDecoder().decode(AgentConversationalTeamJob.self, from: JSONEncoder().encode(job))
    XCTAssertNil(old.source); XCTAssertTrue(old.valid)
    job.source = value.source
    let restored = try JSONDecoder().decode(AgentConversationalTeamJob.self, from: JSONEncoder().encode(job))
    XCTAssertEqual(restored.source, value.source); XCTAssertEqual(try restored.begin().finish("Synthetic result").source, value.source)
  }
  func testOriginalTurnBindingCannotChangeAfterTheJobIsClaimed() throws {
    let suite = "review-source-synthetic-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let value = candidate(), store = AgentConversationalTeamStore(owner: value.owner, defaults: defaults, secrets: InMemorySecretStore())
    var job = AgentConversationalTeamJob(conversation: value.conversation, objective: value.objective,
      route: .init(kind: .local, target: "local-llm", model: "synthetic", endpointSHA: "", host: "",
        artifactSHA: String(repeating: "a", count: 64)))
    job.source = value.source; try store.replace(job, expected: nil)
    var claimed = try job.begin(); claimed.source = .init(message: UUID(), turn: "other-turn")
    XCTAssertThrowsError(try store.replace(claimed, expected: job))
    XCTAssertEqual(try store.read(value.conversation), job)
  }
}
