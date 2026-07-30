import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
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
      spec.definition.members.first { $0.agentId == "researcher" }?.context["_signalasi_agent_knowledge_context"],
      "research-only"
    )
    XCTAssertEqual(
      spec.definition.members.first { $0.agentId == "lead" }?.context["_signalasi_agent_knowledge_context"],
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
}
