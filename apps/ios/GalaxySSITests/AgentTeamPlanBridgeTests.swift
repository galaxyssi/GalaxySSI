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
      sourceMessageId: "source-2"
    )
    var observerPayload: [String: Any] = [:]
    observerContext.apply(to: &observerPayload)

    XCTAssertEqual(observerPayload["agent_instance_id"] as? String, "codex:mention-2")
    XCTAssertEqual(observerPayload["team_id"] as? String, "team-1")
    XCTAssertEqual(observerPayload["agent_team_message"] as? Bool, true)
    XCTAssertEqual(observerPayload["delivery_mode"] as? String, AgentDeliveryMode.observe.rawValue)
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
