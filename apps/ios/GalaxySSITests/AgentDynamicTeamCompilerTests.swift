import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentDynamicTeamCompilerBuildsVerifiedDagFromComplementaryAgents() throws {
    let result = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Research the latest API and implement a Python program with high quality",
        teamId: "dynamic-team"
      ),
      registrations: [
        networkRegistration(
          agentId: "hermes.office",
          displayName: "Hermes - Office PC",
          capabilities: [.chat, .reasoning, .research, .liveData, .toolUse],
          failureDomain: "desktop-office"
        ),
        networkRegistration(
          agentId: "codex.dev",
          displayName: "Codex - Development PC",
          capabilities: [.chat, .reasoning, .code, .taskExecution, .toolUse],
          latency: .fast,
          failureDomain: "desktop-dev"
        ),
        networkRegistration(
          agentId: "claude-code.review",
          displayName: "Claude Code - Review PC",
          capabilities: [.chat, .reasoning, .code, .taskExecution],
          failureDomain: "desktop-review"
        ),
        networkRegistration(
          agentId: "auditor.independent",
          displayName: "Independent Auditor",
          capabilities: [.chat, .reasoning, .research],
          failureDomain: "cloud-audit"
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(result.outcome, .team)
    XCTAssertEqual(result.primaryAgentId, "codex.dev")
    XCTAssertEqual(
      Set(result.assignments.map { $0.registration.agentId }),
      Set(["codex.dev", "hermes.office", "claude-code.review", "auditor.independent"])
    )
    let definition = try XCTUnwrap(result.definition)
    XCTAssertEqual(definition.members.filter { $0.deliveryMode == .respond }.count, 1)
    XCTAssertEqual(definition.collectiveCapabilities, Set([AgentCapability.liveData, AgentCapability.code]))
    let verifier = try XCTUnwrap(definition.members.first { $0.role == "independent verifier" })
    XCTAssertEqual(verifier.dependsOnAgentIds, Set(["hermes.office", "claude-code.review"]))
    let lead = try XCTUnwrap(definition.members.first { $0.agentId == result.primaryAgentId })
    XCTAssertEqual(
      lead.dependsOnAgentIds,
      Set(definition.members.filter { $0.deliveryMode == .observe }.map { $0.agentId })
    )
  }

  func testAgentDynamicTeamCompilerKeepsSimpleConversationSingleAgentAndHonorsPinnedIdentity() {
    let simple = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(goal: "Hello"),
      registrations: [
        networkRegistration(agentId: "hermes", displayName: "Hermes", capabilities: [.chat, .reasoning])
      ],
      nowMillis: 1_000_000
    )
    let pinned = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Discuss the architecture",
        policy: AgentDynamicTeamPolicy(pinnedAgentIds: ["hermes.home"])
      ),
      registrations: [
        networkRegistration(
          agentId: "codex.office",
          displayName: "Codex - Office PC",
          capabilities: [.chat, .reasoning],
          latency: .instant
        ),
        networkRegistration(
          agentId: "hermes.home",
          displayName: "Hermes - Home PC",
          capabilities: [.chat, .reasoning],
          latency: .normal
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(simple.outcome, .singleAgent)
    XCTAssertEqual(simple.primaryAgentId, "hermes")
    XCTAssertNil(simple.definition)
    XCTAssertEqual(pinned.primaryAgentId, "hermes.home")
    XCTAssertEqual(pinned.assignments.first?.registration.displayName, "Hermes - Home PC")
  }

  func testAgentDynamicTeamCompilerAppliesPrivacyVerifierAndRuntimeIdentityBoundaries() {
    let privateResult = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(goal: "Handle my private key locally only"),
      registrations: [
        networkRegistration(
          agentId: "phone.agent",
          displayName: "Phone Agent",
          location: .phone,
          trust: .phoneSystem,
          capabilities: [.chat, .reasoning],
          failureDomain: "phone"
        ),
        networkRegistration(
          agentId: "cloud.agent",
          displayName: "Cloud Agent",
          location: .cloud,
          trust: .cloudConfigured,
          capabilities: [.chat, .reasoning],
          failureDomain: "cloud"
        )
      ],
      nowMillis: 1_000_000
    )
    let sameDomain = [
      networkRegistration(
        agentId: "codex",
        displayName: "Codex",
        capabilities: [.chat, .code, .reasoning],
        failureDomain: "desktop-one"
      ),
      networkRegistration(
        agentId: "claude-code",
        displayName: "Claude Code",
        capabilities: [.chat, .code, .reasoning],
        failureDomain: "desktop-one"
      )
    ]
    let requiredVerifierRequest = AgentDynamicTeamRequest(
      goal: "Implement and verify a Python program",
      policy: AgentDynamicTeamPolicy(verificationMode: .required)
    )
    let blocked = AgentDynamicTeamCompiler().compile(
      request: requiredVerifierRequest,
      registrations: sameDomain,
      nowMillis: 1_000_000
    )
    let verified = AgentDynamicTeamCompiler().compile(
      request: requiredVerifierRequest,
      registrations: sameDomain + [
        networkRegistration(
          agentId: "auditor",
          displayName: "Auditor",
          capabilities: [.chat, .reasoning],
          failureDomain: "desktop-two"
        )
      ],
      nowMillis: 1_000_000
    )
    let aliasBlocked = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Implement and verify a Python program",
        policy: AgentDynamicTeamPolicy(forceTeam: true)
      ),
      registrations: [
        networkRegistration(
          agentId: "codex.alias-one",
          displayName: "Codex",
          capabilities: [.chat, .reasoning, .code],
          failureDomain: "desktop-one",
          runtimeFailureDomain: "desktop-one:codex"
        ),
        networkRegistration(
          agentId: "codex.alias-two",
          displayName: "Codex Alias",
          capabilities: [.chat, .reasoning, .code],
          failureDomain: "desktop-one",
          runtimeFailureDomain: "desktop-one:codex"
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(privateResult.primaryAgentId, "phone.agent")
    XCTAssertFalse(privateResult.assignments.contains { $0.registration.location == .cloud })
    XCTAssertEqual(blocked.outcome, .blocked)
    XCTAssertTrue(blocked.unfilledRoles.contains(.verifier))
    XCTAssertEqual(verified.outcome, .team)
    XCTAssertEqual(verified.assignments.first { $0.role == .verifier }?.failureDomain, "desktop-two")
    XCTAssertEqual(aliasBlocked.outcome, .blocked)
    XCTAssertEqual(aliasBlocked.assignments.count, 1)
  }

  func testAgentDynamicTeamCompilerModelsUseAndroidWireNames() throws {
    let result = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Implement and verify a Python program",
        teamId: "wire-team",
        policy: AgentDynamicTeamPolicy(verificationMode: .required)
      ),
      registrations: [
        networkRegistration(
          agentId: "codex",
          displayName: "Codex",
          capabilities: [.chat, .code, .reasoning],
          failureDomain: "desktop-one"
        ),
        networkRegistration(
          agentId: "auditor",
          displayName: "Auditor",
          capabilities: [.chat, .reasoning],
          failureDomain: "desktop-two"
        )
      ],
      nowMillis: 1_000_000
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    let definition = try XCTUnwrap(object["definition"] as? [String: Any])
    let members = try XCTUnwrap(definition["members"] as? [[String: Any]])

    XCTAssertEqual(object["primary_agent_id"] as? String, "codex")
    XCTAssertEqual(object["estimated_cost_units"] as? Int, 0)
    XCTAssertNotNil(object["unfilled_roles"])
    XCTAssertEqual(definition["team_id"] as? String, "wire-team")
    XCTAssertEqual(definition["primary_agent_id"] as? String, "codex")
    XCTAssertEqual(definition["visibility_mode"] as? String, "BACKGROUND")
    XCTAssertEqual(members.first?["delivery_mode"] as? String, "RESPOND")
    XCTAssertNotNil(members.first?["depends_on_agent_ids"])
    XCTAssertNil(object["primaryAgentId"])
    XCTAssertNil(definition["primaryAgentId"])
  }
}
