import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentTeamPlanBridgeCompilesBranchedGraphIntoOneSupervisedTeamAction() throws {
    let research = teamActionWithAgentKnowledge(
      teamAgentAction("research", "researcher"),
      "research-only"
    )
    let review = teamAgentAction("review", "reviewer")
    let synthesis = teamAgentAction(
      "synthesis",
      "lead",
      dependsOn: ["research", "review"],
      outputSources: ["research", "review"]
    )
    let synthesisWithKnowledge = teamActionWithAgentKnowledge(synthesis, "lead-only")

    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(research, review, synthesisWithKnowledge),
      targets: teamTargets(),
      enabled: true
    )

    XCTAssertEqual(compiled.actions.count, 1)
    let action = try XCTUnwrap(compiled.actions.first)
    XCTAssertTrue(action.id.hasPrefix("agent-team-"))
    XCTAssertTrue(Int64(action.parameters[agentTeamSourceParameter] ?? "0") ?? 0 > 0)
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    XCTAssertEqual(spec.definition.primaryAgentId, "lead")
    XCTAssertEqual(spec.definition.members.count, 3)
    XCTAssertEqual(spec.definition.members.first { $0.agentId == "lead" }?.deliveryMode, .respond)
    XCTAssertEqual(spec.definition.members.first { $0.agentId == "lead" }?.dependsOnAgentIds, Set(["researcher", "reviewer"]))
    XCTAssertTrue(spec.definition.members.filter { $0.agentId != "lead" }.allSatisfy { $0.deliveryMode == .observe })
    XCTAssertEqual(
      spec.definition.members.first { $0.agentId == "researcher" }?.context["_galaxyssi_agent_knowledge_context"],
      "research-only"
    )
    XCTAssertEqual(
      spec.definition.members.first { $0.agentId == "lead" }?.context["_galaxyssi_agent_knowledge_context"],
      "lead-only"
    )
    XCTAssertTrue(compiled.validation.valid)
  }

  func testAgentTeamPlanBridgeRemapsDownstreamDependenciesAndRejectsUnsafeGraphs() {
    let research = teamAgentAction("research", "researcher")
    let synthesis = teamAgentAction(
      "synthesis",
      "lead",
      dependsOn: ["research"],
      outputSources: ["research"]
    )
    let downstream = teamConnectorAction(
      "publish",
      "cloud",
      kind: .model,
      dependsOn: ["synthesis"],
      outputSources: ["synthesis"]
    )
    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(research, synthesis, downstream),
      targets: teamTargets() + [teamTarget("cloud", kind: .model)],
      enabled: true
    )

    XCTAssertEqual(compiled.actions.count, 2)
    let teamId = compiled.actions[0].id
    XCTAssertEqual(compiled.actions[1].parameters["depends_on"], teamId)
    XCTAssertEqual(compiled.actions[1].parameters["use_outputs_from"], teamId)
    XCTAssertTrue(compiled.validation.valid)

    let independent = teamBridgePlan(teamAgentAction("first", "researcher"), teamAgentAction("second", "lead"))
    XCTAssertEqual(
      AgentTeamPlanCompiler.compile(plan: independent, targets: teamTargets(), enabled: true).actions,
      independent.actions
    )

    let external = teamBridgePlan(
      AgentAction(
        id: "phone-step",
        kind: .draftPlan,
        target: "phone",
        risk: .low,
        status: .pendingConfirmation,
        description: "Prepare phone evidence"
      ),
      teamAgentAction("research", "researcher", dependsOn: ["phone-step"]),
      teamAgentAction("synthesis", "lead", dependsOn: ["research"])
    )
    XCTAssertEqual(
      AgentTeamPlanCompiler.compile(plan: external, targets: teamTargets(), enabled: true).actions,
      external.actions
    )
  }

  func testAgentTeamPlanBridgeCompilesComplexSingleAgentPlanIntoDynamicTeam() throws {
    let original = teamBridgePlan(
      goal: "Implement and verify a Python API using current documentation",
      teamAgentAction("implement", "codex")
    )
    let targets = [
      AgentCallableTarget(
        id: "codex",
        title: "Codex - Development PC",
        kind: .agent,
        status: .available,
        capabilities: [.chat, .reasoning, .code, .taskExecution],
        failureDomain: "desktop-development",
        adapterType: "codex-app-server"
      ),
      AgentCallableTarget(
        id: "hermes",
        title: "Hermes - Research PC",
        kind: .agent,
        status: .available,
        capabilities: [.chat, .reasoning, .research, .liveData, .knowledgeSearch],
        failureDomain: "desktop-research",
        adapterType: "hermes-cli"
      )
    ]
    let registrations = targets.map(teamRegistration)

    let compiled = AgentTeamPlanCompiler.compile(
      plan: original,
      targets: targets,
      enabled: true,
      registrations: registrations
    )

    let action = try XCTUnwrap(compiled.actions.first)
    let rawSpecObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data((action.parameters[agentTeamSpecParameter] ?? "").utf8)) as? [String: Any]
    )
    let rawMembers = try XCTUnwrap(rawSpecObject["members"] as? [[String: Any]])
    let codexContext = try XCTUnwrap(
      rawMembers.first { $0["agent_id"] as? String == "codex" }?["context"] as? [String: Any]
    )
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    XCTAssertEqual(spec.definition.primaryAgentId, "codex")
    XCTAssertEqual(Set(spec.definition.members.map(\.agentId)), Set(["codex", "hermes"]))
    XCTAssertEqual(spec.definition.collectiveCapabilities, Set([AgentCapability.code, AgentCapability.liveData, AgentCapability.knowledgeSearch]))
    XCTAssertEqual(codexContext["compiled_role"] as? String, "lead")
    XCTAssertTrue(compiled.validation.valid)

    let simple = teamBridgePlan(goal: "Hello", teamAgentAction("chat", "codex"))
    XCTAssertNil(AgentTeamPlanCompiler.compile(
      plan: simple,
      targets: targets,
      enabled: true,
      registrations: registrations
    ).actions.first?.parameters[agentTeamSpecParameter])
  }

  func testAgentTeamDispatchSpecRejectsMalformedAndRetryRekeysAttempt() throws {
    let valid = AgentTeamDispatchSpec(
      definition: AgentTeamDefinition(
        teamId: "team",
        primaryAgentId: "lead",
        members: [
          AgentTeamMember(
            agentId: "researcher",
            deliveryMode: .observe,
            requiredCapabilities: [],
            role: "research specialist",
            objective: "",
            dependsOnAgentIds: [],
            context: [:]
          ),
          AgentTeamMember(
            agentId: "lead",
            deliveryMode: .respond,
            requiredCapabilities: [],
            role: "lead synthesizer",
            objective: "",
            dependsOnAgentIds: ["researcher"],
            context: [:]
          )
        ],
        visibilityMode: .background,
        collectiveCapabilities: []
      ),
      supervisorRunId: "run"
    )
    let encoded = AgentTeamDispatchSpecCodec.encode(valid)
      .replacingOccurrences(of: "\"delivery_mode\":\"OBSERVE\"", with: "\"delivery_mode\":\"RESPOND\"")

    XCTAssertNil(AgentTeamDispatchSpecCodec.decode(encoded))
    XCTAssertNil(AgentTeamDispatchSpecCodec.decode(#"{"version":1}"#))

    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(
        teamAgentAction("research", "researcher"),
        teamAgentAction("synthesis", "lead", dependsOn: ["research"])
      ),
      targets: teamTargets(),
      enabled: true
    )
    let original = try XCTUnwrap(compiled.actions.first)
    let retry = AgentTeamPlanCompiler.rekeyAgentTeamForRetry(original)
    let originalSpec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(original.parameters[agentTeamSpecParameter] ?? ""))
    let retrySpec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(retry.parameters[agentTeamSpecParameter] ?? ""))

    XCTAssertNotEqual(originalSpec.definition.teamId, retrySpec.definition.teamId)
    XCTAssertNotEqual(originalSpec.supervisorRunId, retrySpec.supervisorRunId)
    XCTAssertNotEqual(originalSpec.sourceMessageId, retrySpec.sourceMessageId)
    XCTAssertEqual(retry.parameters[agentTeamRunParameter], retrySpec.supervisorRunId)
    XCTAssertEqual(retry.parameters[agentTeamSourceParameter], String(retrySpec.sourceMessageId))
  }

  func testAgentTeamPlanBridgeModelsUseAndroidWireNames() throws {
    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(
        teamAgentAction("research", "researcher"),
        teamAgentAction("synthesis", "lead", dependsOn: ["research"])
      ),
      targets: teamTargets(),
      enabled: true
    )
    let action = try XCTUnwrap(compiled.actions.first)
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    let specObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(AgentTeamDispatchSpecCodec.encode(spec).utf8)) as? [String: Any]
    )

    XCTAssertEqual(specObject["supervisor_run_id"] as? String, spec.supervisorRunId)
    XCTAssertEqual(specObject["team_id"] as? String, spec.definition.teamId)
    XCTAssertEqual(specObject["primary_agent_id"] as? String, "lead")
    XCTAssertEqual(specObject["visibility"] as? String, "BACKGROUND")
    XCTAssertNotNil(specObject["collective_capabilities"])
    XCTAssertEqual(action.parameters[agentTeamRunParameter], spec.supervisorRunId)
    XCTAssertEqual(action.parameters[agentTeamSourceParameter], String(spec.sourceMessageId))
    XCTAssertEqual(spec.responseContactId, "agent-team:\(spec.definition.teamId)")
    XCTAssertGreaterThanOrEqual(spec.sourceMessageId, Int64(1) << 62)
    XCTAssertNil(specObject["supervisorRunId"])
    XCTAssertNil(specObject["primaryAgentId"])
  }

  func testAgentMentionParserPreservesRepeatedInstancesAndRoleHints() {
    let targets = [teamTarget("codex")]
    let selection = AgentMentionText.parse(
      "@codex implement the feature\n@codex #2 review the result",
      targets: targets
    )

    XCTAssertEqual(selection.requestedMembers.map(\.agentId), ["codex", "codex"])
    XCTAssertEqual(selection.requestedMembers.map(\.instanceId), [
      "codex:mention-1",
      "codex:mention-2"
    ])
    XCTAssertTrue(selection.requestedMembers[0].roleHint.contains("implement"))
    XCTAssertTrue(selection.requestedMembers[1].roleHint.contains("review"))
    XCTAssertFalse(selection.goal.contains("@codex"))
  }

  func testCollaborationMentionUsesMemberIDAndIgnoresUntrustedEvidence() {
    let first = AgentCollaborationRoster.Member(name: "Same", resourceId: "codex")
    let second = AgentCollaborationRoster.Member(name: "Same", resourceId: "codex")
    var roster = AgentCollaborationRoster(members: [first, second], coordinatorId: first.id)
    let draft = AgentCollaborationMentionText.inserting(second, into: "Review @Sa") + "the report"
    let evidence = AgentUntrustedEvidenceBoundary.textMarker + "\n" +
      AgentCollaborationMentionText.inserting(first, into: "@")
    roster.members[1].name = "Renamed"
    let result = AgentCollaborationMentionText.parse(draft + "\n\n" + evidence, roster: roster)
    XCTAssertEqual(result.memberIds, [second.id])
    XCTAssertTrue(result.goal.contains("the report"))
    XCTAssertTrue(result.displayText.contains("@Renamed"))
    XCTAssertFalse(result.goal.contains(second.id.uuidString.lowercased()))
    XCTAssertTrue(result.goal.contains(first.id.uuidString.lowercased()))
  }

  func testIndependentFollowupSelectsExactRespondentWithoutReusingResearchStages() throws {
    let coordinator = AgentCollaborationRoster.Member(name: "Lead", resourceId: "codex")
    let reviewer = AgentCollaborationRoster.Member(name: "Reviewer", resourceId: "another",
      modelId: "selected-model", mentionOnly: true)
    let original = AgentCollaborationRoster(members: [coordinator, reviewer], coordinatorId: coordinator.id,
      independentReview: true, workflow: .research)
    let implicit = try XCTUnwrap(AgentTeamPlanCompiler.followupRoster(original, mentioned: []))
    XCTAssertEqual(implicit.members.map(\.id), [coordinator.id])
    let explicit = try XCTUnwrap(AgentTeamPlanCompiler.followupRoster(original, mentioned: [reviewer.id]))
    XCTAssertEqual(explicit.coordinatorId, reviewer.id)
    XCTAssertEqual(explicit.members.map(\.modelId), [reviewer.modelId])
    XCTAssertEqual(explicit.workflow, .parallel)
    XCTAssertFalse(explicit.independentReview)
    XCTAssertEqual(original.workflow, .research)
    XCTAssertNil(AgentTeamPlanCompiler.followupRoster(original, mentioned: [UUID()]))
  }

  func testResourceObservationUsesOnlyTheSelectedRuntimePool() throws {
    var registration = teamRegistration(teamTarget("codex"))
    registration.maxParallelRuns = 2
    let runtime = AgentRuntimeIdentity.key(registration)
    let observation = AgentCollaborationResourceObservation.record(registration: registration,
      activeCounts: [runtime: 3, "unrelated-runtime": 7], now: 12)
    let prompt = AgentCollaborationResourceObservation.prompt(observation)
    let json = try XCTUnwrap(prompt.split(separator: "\n").dropFirst().first)
    let record = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(json.utf8))
    XCTAssertEqual(record["admission_limit"], .int(2))
    XCTAssertEqual(record["admissions_reserved"], .int(3))
    XCTAssertEqual(record["admissions_remaining_at_observation"], .int(0))
    XCTAssertEqual(record["provider_request_count"], .null)
    XCTAssertEqual(record["remaining_window_ms_at_observation"], .null)
  }

  func testStagedCollaborationSchedulesExplorationBeforeReviewAndSynthesis() throws {
    let target = teamTarget("codex")
    var registration = teamRegistration(target)
    registration.maxParallelRuns = 3
    let coordinator = AgentCollaborationRoster.Member(name: "Lead", resourceId: target.id)
    let explorer = AgentCollaborationRoster.Member(name: "Explorer", resourceId: target.id)
    let reviewer = AgentCollaborationRoster.Member(name: "Reviewer", resourceId: target.id)
    let roster = AgentCollaborationRoster(members: [coordinator, explorer, reviewer],
      coordinatorId: coordinator.id, workflow: .research)
    let plan = teamBridgePlan(goal: "Evaluate alternatives", teamAgentAction("work", target.id))
    let compiled = try XCTUnwrap(AgentTeamPlanCompiler.compileCollaboration(
      plan: plan, roster: roster, targets: [target], registrations: [registration]))
    let wire = try XCTUnwrap(compiled.actions.first?.parameters[agentTeamSpecParameter])
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(wire))
    let order = try XCTUnwrap(AgentTeamPlanCompiler.collaborationDispatchOrder(spec.definition.members))
    XCTAssertEqual(order.map { $0.context["_galaxyssi_research_stage"] ?? "" },
      ["EXPLORE", "CHALLENGE", "REVISE", "RECHECK", "DELIVER"])
    XCTAssertEqual(order[1].dependsOnAgentIds, [order[0].memberId])
    XCTAssertEqual(order[2].dependsOnAgentIds, [order[0].memberId, order[1].memberId])
    XCTAssertEqual(order[3].dependsOnAgentIds, [order[1].memberId, order[2].memberId])
    XCTAssertEqual(order[4].dependsOnAgentIds, Set(order.dropLast().map(\.memberId)))
    XCTAssertEqual(order[0].context["_galaxyssi_roster_member_id"], order[2].context["_galaxyssi_roster_member_id"])
    XCTAssertNotEqual(order[0].memberId, order[2].memberId)
    var cyclic = order
    cyclic[0].dependsOnAgentIds = [order[2].memberId]
    XCTAssertNil(AgentTeamPlanCompiler.collaborationDispatchOrder(cyclic))
  }

  func testCollaborationCompilationPreservesRosterIdentityAndRejectsCapacityOverflow() throws {
    var target = teamTarget("codex")
    target.adapterType = "codex-app-server-or-cli"
    target.invocationProfile = AgentInvocationProfile(models: [.init(id: "review-model")], reasoningEfforts: [.xhigh])
    var registration = teamRegistration(target)
    registration.maxParallelRuns = 3
    let coordinator = AgentCollaborationRoster.Member(name: "Lead", role: "Synthesis", resourceId: target.id)
    let reviewer = AgentCollaborationRoster.Member(name: "Reviewer", role: "Evidence review",
      resourceId: target.id, modelId: "review-model", mentionOnly: true, reasoningEffort: "xhigh")
    let researcher = AgentCollaborationRoster.Member(name: "Researcher", resourceId: target.id)
    let roster = AgentCollaborationRoster(members: [researcher, reviewer, coordinator],
      coordinatorId: coordinator.id, independentReview: true)
    let plan = teamBridgePlan(goal: "Check evidence", teamAgentAction("work", target.id))
    let compiled = try XCTUnwrap(AgentTeamPlanCompiler.compileCollaboration(plan: plan,
      roster: roster, mentionedMemberIds: [reviewer.id], targets: [target], registrations: [registration]))
    let action = try XCTUnwrap(compiled.actions.first)
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    let reviewerId = reviewer.id.uuidString.lowercased()
    XCTAssertEqual(spec.definition.primaryMemberId, coordinator.id.uuidString.lowercased())
    XCTAssertEqual(spec.definition.members.map(\.memberId), [reviewerId, coordinator.id.uuidString.lowercased()])
    XCTAssertEqual(spec.definition.members.first?.role, "Evidence review")
    XCTAssertEqual(spec.definition.members.first?.context["_galaxyssi_member_model_id"], "review-model")
    XCTAssertEqual(spec.definition.members.first?.context[AgentCollaborationReasoningSelection.contextKey], "xhigh")
    XCTAssertNil(spec.definition.members.last?.context[AgentCollaborationReasoningSelection.contextKey])
    XCTAssertEqual(AgentCollaborationReasoningSelection.invocation(model: "review-model", effort: "xhigh",
      adapter: target.adapterType, profile: target.invocationProfile),
      ["model_id": "review-model", "reasoning_effort": "xhigh"])
    XCTAssertNil(AgentCollaborationReasoningSelection.invocation(model: "review-model", effort: "auto",
      adapter: target.adapterType, profile: target.invocationProfile))
    var changedTarget = target
    changedTarget.invocationProfile.reasoningEfforts = [.high]
    XCTAssertNil(AgentTeamPlanCompiler.compileCollaboration(plan: plan, roster: roster,
      mentionedMemberIds: [reviewer.id], targets: [changedTarget], registrations: [registration]))
    XCTAssertEqual(spec.definition.members.last?.dependsOnAgentIds, [reviewerId])
    registration.maxParallelRuns = 1
    XCTAssertNil(AgentTeamPlanCompiler.compileCollaboration(plan: plan,
      roster: roster, mentionedMemberIds: [reviewer.id], targets: [target], registrations: [registration]))
    XCTAssertNil(AgentTeamPlanCompiler.compileCollaboration(plan: plan,
      roster: roster, mentionedMemberIds: [UUID()], targets: [target], registrations: [registration]))
  }

  func testGoalAssessmentPreservesContractAndRequiresMatchingHostEvidence() throws {
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    let original = Policy.Criterion(id: "physical-test", requirement: "Observe the physical result",
      verification: .physical, status: .open, evidence_kind: nil, evidence: [])
    var current = original
    current.status = .met
    current.evidence_kind = .observed
    current.evidence = ["receipt-1"]
    var assessment = Policy.Assessment(format: "galaxyssi.goal-assessment.v1", summary: "Result",
      decision: .achieved, criteria: [current], work: [], blockers: [])
    let verified = ["physical-test": Policy.VerifiedCriterion(requirement: original.requirement,
      verification: .physical, evidence: ["receipt-1"])]
    func evaluate(_ receipts: [String: Policy.VerifiedCriterion]) throws -> Policy.Outcome {
      let raw = String(decoding: try JSONEncoder().encode(assessment), as: UTF8.self)
      return Policy.evaluate(raw, preserving: [original], authorizedMembers: [],
        completedWork: [], verified: receipts)
    }
    XCTAssertEqual(try evaluate([:]), .needsAssessment)
    XCTAssertEqual(try evaluate(verified), .achieved)
    assessment.criteria[0].evidence_kind = .simulation
    XCTAssertEqual(try evaluate(verified), .needsAssessment)
    assessment.criteria[0].verification = .computational
    XCTAssertEqual(try evaluate(verified), .needsAssessment)
    assessment.criteria = []
    XCTAssertEqual(try evaluate(verified), .needsAssessment)
  }

  func testGoalAssessmentDoesNotRescheduleCompletedWork() throws {
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    let criterion = Policy.Criterion(id: "delivery", requirement: "Deliver evidence",
      verification: .documentary, status: .open, evidence_kind: nil, evidence: [])
    let assessment = Policy.Assessment(format: "galaxyssi.goal-assessment.v1", summary: "More work",
      decision: .continue, criteria: [criterion],
      work: [Policy.Work(id: "check", member: "researcher", assignment: "Check evidence")], blockers: [])
    let raw = String(decoding: try JSONEncoder().encode(assessment), as: UTF8.self)
    XCTAssertEqual(Policy.evaluate(raw, preserving: [criterion], authorizedMembers: ["researcher"],
      completedWork: []), .schedule(["check"]))
    XCTAssertEqual(Policy.evaluate(raw, preserving: [criterion], authorizedMembers: ["researcher"],
      completedWork: ["check"]), .needsAssessment)
    XCTAssertEqual(Policy.evaluate(raw, preserving: [criterion], authorizedMembers: [],
      completedWork: []), .needsAssessment)
  }

  func testDocumentaryAcceptanceRequiresIndependentReviewOfExactCurrentVersion() throws {
    typealias Gate = AgentCollaborationDocumentaryAcceptance
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    let deliveryRef = Gate.Reference(objectId: "delivery", revision: 1, sha256: String(repeating: "a", count: 64))
    let reviewRef = Gate.Reference(objectId: "review", revision: 1, sha256: String(repeating: "b", count: 64))
    var delivery = Gate.Revision(reference: deliveryRef, conversationId: "group", runId: "run",
      turnId: "turn", authorId: "author", kind: "artifact", body: ["content": .string("Report")],
      parents: [], hostObservationIds: ["observed"])
    let reviewBody: AgentMcpJSONObject = ["acceptance_review": .object([
      "criterion_id": .string("report"), "requirement": .string("Deliver report"),
      "target": .object(["object_id": .string("delivery"), "revision": .int(1), "sha256": .string(deliveryRef.sha256)]),
      "verdict": .string("supported"), "rationale": .string("Checked report against the requirement"),
      "unresolved": .array([])
    ])]
    var review = Gate.Revision(reference: reviewRef, conversationId: "group", runId: "run",
      turnId: "turn", authorId: "reviewer", kind: "decision", body: reviewBody,
      parents: [deliveryRef], hostObservationIds: [])
    var original = Policy.Criterion(id: "report", requirement: "Deliver report",
      verification: .documentary, status: .open, evidence_kind: nil, evidence: [])
    original.required_observations = [.init(origin: "ios_cloud_tool", tool: "web_search")]
    review.hostObservationIds = ["observed"]
    var met = original
    met.status = .met
    met.evidence_kind = .observed
    met.evidence = ["delivery", "observed"]
    met.delivery = deliveryRef
    met.review = reviewRef
    let assessment = Policy.Assessment(format: "galaxyssi.goal-assessment.v1", summary: "Report delivered",
      decision: .achieved, criteria: [met], work: [], blockers: [])
    let raw = String(decoding: try JSONEncoder().encode(assessment), as: UTF8.self)
    func check(observationAvailable: Bool = true, originalTool: String = "web_search") -> Policy.Outcome {
      Gate.evaluate(raw, preserving: [original], conversationId: "group", runId: "run", turnId: "turn",
        readRevision: { id, _ in id == "delivery" ? delivery : (id == "review" ? review : nil) },
        observationIsSupporting: { $0 == "observed" && observationAvailable },
        originalObservation: { id in
          id == "observed" ? .init(origin: "ios_cloud_tool", tool: originalTool,
            status: "returned", kind: "tool_output_recorded") : nil
        })
    }
    XCTAssertEqual(check(), .achieved)
    XCTAssertEqual(check(observationAvailable: false), .needsAssessment)
    XCTAssertEqual(check(originalTool: "collaboration_recall"), .needsAssessment)
    review.authorId = delivery.authorId
    XCTAssertEqual(check(), .needsAssessment)
    review.authorId = "reviewer"
    delivery.reference.revision = 2
    XCTAssertEqual(check(), .needsAssessment)
    delivery.reference = deliveryRef
    review.turnId = "older-turn"
    XCTAssertEqual(check(), .needsAssessment)
  }

  func testComputationalAcceptanceReplaysPinnedNumericCases() throws {
    typealias Gate = AgentCollaborationDocumentaryAcceptance
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    let deliveryRef = Gate.Reference(objectId: "delivery", revision: 1, sha256: String(repeating: "a", count: 64))
    let reviewRef = Gate.Reference(objectId: "review", revision: 1, sha256: String(repeating: "b", count: 64))
    let requirement = AgentCollaborationNumericTrial.requirement
    let validator: AgentMcpJSONObject = ["id": .string(AgentCollaborationNumericTrial.validatorId),
      "variables": .array([.string("x")]), "cases": .array([.object([
        "id": .string("registered"), "input": .object(["x": .int(4)]),
        "expected": .int(4), "absolute_tolerance": .int(0)
      ])])]
    let original = Policy.Criterion(id: "numeric", requirement: requirement, verification: .computational,
      status: .open, evidence_kind: nil, evidence: [], validator: validator)
    var met = original
    met.status = .met
    met.evidence_kind = .observed
    met.evidence = ["delivery"]
    met.delivery = deliveryRef
    met.review = reviewRef
    let review = Gate.Revision(reference: reviewRef, conversationId: "group", runId: "run", turnId: "turn",
      authorId: "reviewer", kind: "acceptance_review", body: ["acceptance_review": .object([
        "criterion_id": .string("numeric"), "requirement": .string(requirement),
        "target": .object(["object_id": .string("delivery"), "revision": .int(1), "sha256": .string(deliveryRef.sha256)]),
        "verdict": .string("supported"), "rationale": .string("Recomputed the case"), "unresolved": .array([])
      ])], parents: [deliveryRef], hostObservationIds: [])
    func assess(_ criterion: Policy.Criterion, model: AgentMcpJSONObject) throws -> Policy.Outcome {
      let delivery = Gate.Revision(reference: deliveryRef, conversationId: "group", runId: "run", turnId: "turn",
        authorId: "author", kind: "artifact", body: ["content": .string("Saved calculation"), "computation": .object([
          "validator_id": .string(AgentCollaborationNumericTrial.validatorId), "model": .object(model)
        ])], parents: [], hostObservationIds: [])
      let assessment = Policy.Assessment(format: "galaxyssi.goal-assessment.v1", summary: "Numeric result",
        decision: .achieved, criteria: [criterion], work: [], blockers: [])
      let raw = String(decoding: try JSONEncoder().encode(assessment), as: UTF8.self)
      return Gate.evaluate(raw, preserving: [original], conversationId: "group", runId: "run", turnId: "turn",
        readRevision: { id, _ in id == "delivery" ? delivery : (id == "review" ? review : nil) },
        observationIsSupporting: { _ in false })
    }
    XCTAssertEqual(try assess(met, model: ["variable": .string("x")]), .achieved)
    XCTAssertEqual(try assess(met, model: ["constant": .int(0)]), .needsAssessment)
    met.validator = nil
    XCTAssertEqual(try assess(met, model: ["variable": .string("x")]), .needsAssessment)
  }

  func testRequestedRepeatedAgentCompilesToInstanceScopedTeam() throws {
    let target = teamTarget("codex")
    var registration = teamRegistration(target)
    registration.maxParallelRuns = 2
    let requested = [
      AgentRequestedMember(agentId: "codex", displayName: "Codex", occurrence: 1, roleHint: "implement"),
      AgentRequestedMember(agentId: "codex", displayName: "Codex", occurrence: 2, roleHint: "review")
    ]
    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(goal: "Implement and review", teamAgentAction("work", "codex")),
      targets: [target],
      enabled: true,
      registrations: [registration],
      requestedMembers: requested
    )
    let action = try XCTUnwrap(compiled.actions.first)
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(
      action.parameters[agentTeamSpecParameter] ?? ""
    ))

    XCTAssertEqual(spec.definition.primaryMemberId, "codex:mention-1")
    XCTAssertEqual(spec.definition.members.map(\.memberId), [
      "codex:mention-1",
      "codex:mention-2"
    ])
    XCTAssertEqual(spec.definition.members[0].dependsOnAgentIds, ["codex:mention-2"])
    XCTAssertEqual(action.parameters["agent_selection_source"], "user_mention")
  }

  func testTeamMailboxRoutesAndAdvancesDeliveryStateIdempotently() throws {
    let mailbox = InMemoryAgentTeamMailbox()
    let direct = AgentTeamMessageEnvelope(
      messageId: "message-1",
      teamId: "team",
      conversationId: "conversation",
      supervisorRunId: "run",
      fromInstanceId: "user",
      toInstanceId: "codex:mention-2",
      kind: .userDirective,
      text: "Review the current result",
      createdAtMillis: 100
    )
    let broadcast = AgentTeamMessageEnvelope(
      messageId: "message-2",
      teamId: "team",
      conversationId: "conversation",
      supervisorRunId: "run",
      fromInstanceId: "user",
      kind: .control,
      text: "Stop after the current step",
      createdAtMillis: 101
    )

    XCTAssertEqual(try mailbox.append(direct).sequence, 1)
    XCTAssertEqual(try mailbox.append(direct).sequence, 1)
    XCTAssertEqual(try mailbox.append(broadcast).sequence, 2)
    XCTAssertEqual(
      mailbox.messages(supervisorRunId: "run", instanceId: "codex:mention-1", afterSequence: 0)
        .map(\.messageId),
      ["message-2"]
    )
    XCTAssertEqual(
      mailbox.messages(supervisorRunId: "run", instanceId: "codex:mention-2", afterSequence: 0)
        .map(\.messageId),
      ["message-1", "message-2"]
    )
    XCTAssertEqual(mailbox.markDelivered(messageId: "message-1", atMillis: 120)?.state, .delivered)
    XCTAssertEqual(mailbox.acknowledge(messageId: "message-1", atMillis: 130)?.state, .acknowledged)
    XCTAssertEqual(mailbox.markDelivered(messageId: "message-1", atMillis: 140)?.state, .acknowledged)
  }

  func testOutboundTeamContextUsesAndroidMqttFieldsAndInstanceScopedRunId() {
    let observer = AgentTeamMember(
      agentId: "codex",
      deliveryMode: .observe,
      requiredCapabilities: [.code],
      role: "reviewer",
      objective: "Review the implementation",
      dependsOnAgentIds: [],
      context: [:],
      instanceId: "codex:mention-2"
    )
    let observerContext = AgentOutboundTeamContext(
      teamId: "team-1",
      supervisorRunId: "run-1",
      primaryInstanceId: "codex:mention-1",
      member: observer,
      sourceMessageId: "source-2",
      executionPolicyPrompt: "Research and compare two primary sources"
    )
    var observerPayload: [String: Any] = [:]
    observerContext.apply(to: &observerPayload)

    XCTAssertEqual(observerPayload["agent_instance_id"] as? String, "codex:mention-2")
    XCTAssertEqual(observerPayload["team_id"] as? String, "team-1")
    XCTAssertEqual(observerPayload["agent_team_message"] as? Bool, true)
    XCTAssertEqual(observerPayload["delivery_mode"] as? String, AgentDeliveryMode.observe.rawValue)
    XCTAssertEqual(
      observerPayload[AgentExecutionPolicyPrompt.wireKey] as? String,
      "Research and compare two primary sources"
    )
    XCTAssertNotEqual(observerPayload["run_id"] as? String, "run-1")

    var primary = observer
    primary.deliveryMode = .respond
    primary.instanceId = "codex:mention-1"
    let primaryContext = AgentOutboundTeamContext(
      teamId: "team-1",
      supervisorRunId: "run-1",
      primaryInstanceId: "codex:mention-1",
      member: primary,
      sourceMessageId: "source-1"
    )
    var primaryPayload: [String: Any] = [:]
    primaryContext.apply(to: &primaryPayload)

    XCTAssertEqual(primaryPayload["agent_instance_id"] as? String, "codex:mention-1")
    XCTAssertEqual(primaryPayload["run_id"] as? String, "run-1")
    XCTAssertNotEqual(primaryContext.sourceMessageId, observerContext.sourceMessageId)
  }
}
