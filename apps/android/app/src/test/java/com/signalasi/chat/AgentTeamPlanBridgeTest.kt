package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTeamPlanBridgeTest {
    @Test
    fun `supervised phone project planner is never expanded into a desktop team`() {
        val action = AgentAction(
            id = "phone-planner",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PROPOSED,
            description = "Plan phone work",
            parameters = mapOf(
                "connector_id" to "codex",
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                INTERNAL_TASK_EXECUTION_MODE to AgentTaskExecutionMode.PLAN_ONLY.wireValue
            ),
            requiresConfirmation = false
        )
        val original = plan(action)

        val compiled = AgentTeamPlanCompiler.compile(original, targets(), enabled = true)

        assertEquals(original, compiled)
    }
    @Test
    fun branchedAgentGraphCompilesIntoOneSupervisedTeamAction() {
        val research = agentAction("research", "researcher").withAgentKnowledge("research-only")
        val review = agentAction("review", "reviewer")
        val synthesis = agentAction(
            id = "synthesis",
            connectorId = "lead",
            dependsOn = listOf("research", "review"),
            outputSources = listOf("research", "review")
        ).withAgentKnowledge("lead-only")

        val compiled = AgentTeamPlanCompiler.compile(
            plan = plan(research, review, synthesis),
            targets = targets(),
            enabled = true
        )

        assertEquals(1, compiled.actions.size)
        val action = compiled.actions.single()
        assertTrue(action.id.startsWith("agent-team-"))
        assertTrue(action.parameters[AGENT_TEAM_SOURCE_PARAMETER]!!.toLong() > 0L)
        val spec = AgentTeamDispatchSpecCodec.decode(action.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty())
        assertNotNull(spec)
        assertEquals("lead", spec!!.definition.primaryAgentId)
        assertEquals(3, spec.definition.members.size)
        assertEquals(
            AgentDeliveryMode.RESPOND,
            spec.definition.members.single { it.agentId == "lead" }.deliveryMode
        )
        assertEquals(
            setOf("researcher", "reviewer"),
            spec.definition.members.single { it.agentId == "lead" }.dependsOnAgentIds
        )
        assertTrue(spec.definition.members.filter { it.agentId != "lead" }.all {
            it.deliveryMode == AgentDeliveryMode.OBSERVE
        })
        assertEquals(
            "research-only",
            spec.definition.members.single { it.agentId == "researcher" }
                .context["_signalasi_agent_knowledge_context"]
        )
        assertEquals(
            "lead-only",
            spec.definition.members.single { it.agentId == "lead" }
                .context["_signalasi_agent_knowledge_context"]
        )
        assertTrue(compiled.validation.valid)
    }

    @Test
    fun downstreamOutputDependencyIsRemappedToTheTeamResult() {
        val research = agentAction("research", "researcher")
        val synthesis = agentAction(
            id = "synthesis",
            connectorId = "lead",
            dependsOn = listOf("research"),
            outputSources = listOf("research")
        )
        val downstream = connectorAction(
            id = "publish",
            connectorId = "cloud",
            dependsOn = listOf("synthesis"),
            outputSources = listOf("synthesis")
        )

        val compiled = AgentTeamPlanCompiler.compile(
            plan = plan(research, synthesis, downstream),
            targets = targets() + target("cloud", AgentConnectorKind.MODEL),
            enabled = true
        )

        assertEquals(2, compiled.actions.size)
        val teamId = compiled.actions.first().id
        assertEquals(listOf(teamId), compiled.actions.last().dependencyIds())
        assertEquals(listOf(teamId), compiled.actions.last().outputSourceIds())
        assertTrue(compiled.validation.valid)
    }

    @Test
    fun independentRespondersRemainOrdinaryActions() {
        val original = plan(
            agentAction("first", "researcher"),
            agentAction("second", "lead")
        )

        val compiled = AgentTeamPlanCompiler.compile(original, targets(), enabled = true)

        assertEquals(original.actions, compiled.actions)
    }

    @Test
    fun complexSingleAgentPlanCompilesAvailableNamedAgentsIntoDynamicTeam() {
        val original = plan(agentAction("implement", "codex")).copy(
            goal = "Implement and verify a Python API using current documentation"
        )
        val targets = listOf(
            AgentCallableTarget(
                id = "codex",
                title = "Codex - Development PC",
                kind = AgentConnectorKind.AGENT,
                status = AgentConnectorStatus.AVAILABLE,
                capabilities = listOf(
                    AgentCapability.CHAT,
                    AgentCapability.REASONING,
                    AgentCapability.CODE,
                    AgentCapability.TASK_EXECUTION
                ),
                failureDomain = "desktop-development",
                adapterType = "codex-app-server"
            ),
            AgentCallableTarget(
                id = "hermes",
                title = "Hermes - Research PC",
                kind = AgentConnectorKind.AGENT,
                status = AgentConnectorStatus.AVAILABLE,
                capabilities = listOf(
                    AgentCapability.CHAT,
                    AgentCapability.REASONING,
                    AgentCapability.RESEARCH,
                    AgentCapability.LIVE_DATA,
                    AgentCapability.KNOWLEDGE_SEARCH
                ),
                failureDomain = "desktop-research",
                adapterType = "hermes-cli"
            )
        )

        val registrations = targetRegistrations(targets)
        val dynamic = AgentDynamicTeamCompiler().compile(
            AgentDynamicTeamRequest(
                goal = original.goal,
                policy = AgentDynamicTeamPolicy(pinnedAgentIds = setOf("codex"))
            ),
            registrations
        )
        assertEquals(
            "Dynamic compilation failed: ${dynamic.outcome}, ${dynamic.warnings}",
            AgentDynamicTeamOutcome.TEAM,
            dynamic.outcome
        )

        val compiled = AgentTeamPlanCompiler.compile(
            plan = original,
            targets = targets,
            enabled = true,
            registrations = registrations
        )

        val action = compiled.actions.single()
        assertTrue(
            "Dynamic bridge did not attach a team spec; validation=${compiled.validation.issues}",
            action.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty().isNotBlank()
        )
        val spec = requireNotNull(
            AgentTeamDispatchSpecCodec.decode(action.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty())
        )
        assertEquals("codex", spec.definition.primaryAgentId)
        assertEquals(setOf("codex", "hermes"), spec.definition.members.mapTo(linkedSetOf()) { it.agentId })
        assertEquals(
            setOf(
                AgentCapability.CODE,
                AgentCapability.KNOWLEDGE_SEARCH
            ),
            spec.definition.collectiveCapabilities
        )
        assertTrue(compiled.validation.valid)
    }

    @Test
    fun simpleSingleAgentPlanDoesNotCreateAnUnnecessaryDynamicTeam() {
        val original = plan(agentAction("chat", "codex")).copy(goal = "Hello")
        val targets = listOf(
            target("codex", AgentConnectorKind.AGENT, AgentCapability.CHAT),
            target("hermes", AgentConnectorKind.AGENT, AgentCapability.CHAT)
        )

        val compiled = AgentTeamPlanCompiler.compile(
            plan = original,
            targets = targets,
            enabled = true,
            registrations = targetRegistrations(targets)
        )

        assertEquals(original.actions, compiled.actions)
        assertNull(compiled.actions.single().parameters[AGENT_TEAM_SPEC_PARAMETER])
    }

    @Test
    fun explicitMultiAgentRequestOverridesASingleNativeToolFallback() {
        val codex = target("codex", AgentConnectorKind.AGENT, AgentCapability.CODE)
        val deepseek = target("deepseek", AgentConnectorKind.MODEL, AgentCapability.REASONING)
        val nativeFallback = AgentAction(
            id = "memory-status",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "phone",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Read current memory status",
            parameters = mapOf("tool_id" to "signalasi.hardware.memory.status")
        )
        val original = plan(nativeFallback).copy(
            goal = "Use multiple Agents to estimate model memory; one should calculate and another should audit"
        )

        val compiled = AgentTeamPlanCompiler.compile(
            plan = original,
            targets = listOf(codex, deepseek),
            enabled = true,
            registrations = targetRegistrations(listOf(codex, deepseek))
        )

        val action = compiled.actions.single()
        val spec = requireNotNull(
            AgentTeamDispatchSpecCodec.decode(action.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty())
        )
        assertEquals("explicit_multi_agent", action.parameters["agent_selection_source"])
        assertNull(action.parameters["manual_target_locked"])
        assertEquals(
            setOf("codex", "deepseek"),
            spec.definition.members.mapTo(linkedSetOf()) { it.agentId }
        )
        assertEquals(1, spec.definition.members.count { it.deliveryMode == AgentDeliveryMode.RESPOND })
        assertTrue(compiled.validation.valid)
    }

    @Test
    fun repeatedAgentIdentityCannotBecomeAHostTeam() {
        val original = plan(
            agentAction("first", "researcher"),
            agentAction("second", "researcher", dependsOn = listOf("first"))
        )

        val compiled = AgentTeamPlanCompiler.compile(original, targets(), enabled = true)

        assertEquals(original.actions, compiled.actions)
    }

    @Test
    fun externalPrerequisitePreventsUnsafePartialCompilation() {
        val prerequisite = AgentAction(
            id = "phone-step",
            kind = AgentActionKind.DRAFT_PLAN,
            target = "phone",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Prepare phone evidence"
        )
        val research = agentAction("research", "researcher", dependsOn = listOf("phone-step"))
        val synthesis = agentAction("synthesis", "lead", dependsOn = listOf("research"))
        val original = plan(prerequisite, research, synthesis)

        val compiled = AgentTeamPlanCompiler.compile(original, targets(), enabled = true)

        assertEquals(original.actions, compiled.actions)
    }

    @Test
    fun malformedOrMultiResponderSpecsAreRejected() {
        val valid = AgentTeamDispatchSpec(
            AgentTeamDefinition(
                teamId = "team",
                primaryAgentId = "lead",
                members = listOf(
                    AgentTeamMember("researcher", AgentDeliveryMode.OBSERVE),
                    AgentTeamMember("lead", AgentDeliveryMode.RESPOND)
                )
            ),
            supervisorRunId = "run"
        )
        val encoded = AgentTeamDispatchSpecCodec.encode(valid)
            .replace("\"delivery_mode\":\"OBSERVE\"", "\"delivery_mode\":\"RESPOND\"")

        assertNull(AgentTeamDispatchSpecCodec.decode(encoded))
        assertNull(AgentTeamDispatchSpecCodec.decode("{\"version\":1}"))
    }

    @Test
    fun dispatchCodecKeepsTwoInstancesOfTheSameAgentIndependent() {
        val source = AgentTeamDispatchSpec(
            AgentTeamDefinition(
                teamId = "two-codex",
                primaryAgentId = "codex",
                primaryInstanceId = "codex-implementer",
                members = listOf(
                    AgentTeamMember(
                        "codex",
                        AgentDeliveryMode.RESPOND,
                        instanceId = "codex-implementer"
                    ),
                    AgentTeamMember(
                        "codex",
                        AgentDeliveryMode.OBSERVE,
                        instanceId = "codex-reviewer"
                    )
                )
            ),
            supervisorRunId = "run"
        )

        val decoded = requireNotNull(
            AgentTeamDispatchSpecCodec.decode(AgentTeamDispatchSpecCodec.encode(source))
        )

        assertEquals("codex-implementer", decoded.definition.primaryMemberId)
        assertEquals(
            listOf("codex-implementer", "codex-reviewer"),
            decoded.definition.members.map(AgentTeamMember::memberId)
        )
    }

    @Test
    fun plannerAllowsTwoInstancesWhenProviderAdvertisesParallelCapacity() {
        val codexTarget = target("codex", AgentConnectorKind.AGENT, AgentCapability.CODE)
        val registration = targetRegistrations(listOf(codexTarget)).single().copy(maxParallelRuns = 2)
        val compiled = AgentTeamPlanCompiler.compile(
            plan = plan(
                agentAction("review", "codex"),
                agentAction("implement", "codex", dependsOn = listOf("review"))
            ),
            targets = listOf(codexTarget),
            enabled = true,
            registrations = listOf(registration)
        )

        val spec = requireNotNull(AgentTeamDispatchSpecCodec.decode(
            compiled.actions.single().parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty()
        ))

        assertEquals(2, spec.definition.members.size)
        assertEquals(1, spec.definition.members.map(AgentTeamMember::agentId).distinct().size)
        assertEquals(2, spec.definition.members.map(AgentTeamMember::memberId).distinct().size)
        assertEquals("codex:implement", spec.definition.primaryMemberId)
    }

    @Test
    fun plannerKeepsSeparateActionsWhenProviderCannotRunTwoInstances() {
        val codexTarget = target("codex", AgentConnectorKind.AGENT, AgentCapability.CODE)
        val registration = targetRegistrations(listOf(codexTarget)).single().copy(maxParallelRuns = 1)
        val original = plan(
            agentAction("review", "codex"),
            agentAction("implement", "codex", dependsOn = listOf("review"))
        )

        val compiled = AgentTeamPlanCompiler.compile(
            plan = original,
            targets = listOf(codexTarget),
            enabled = true,
            registrations = listOf(registration)
        )

        assertEquals(original.actions, compiled.actions)
    }

    @Test
    fun userMentionsCreateAnExactTeamWithRepeatedAgentInstances() {
        val codex = target("codex", AgentConnectorKind.AGENT, AgentCapability.CODE)
        val claude = target("claude", AgentConnectorKind.AGENT, AgentCapability.REASONING)
        val registrations = targetRegistrations(listOf(codex, claude)).map { registration ->
            if (registration.agentId == "codex") registration.copy(maxParallelRuns = 2) else registration
        }

        val compiled = AgentTeamPlanCompiler.compile(
            plan = plan(agentAction("fallback", "codex")),
            targets = listOf(codex, claude),
            enabled = false,
            registrations = registrations,
            requestedMembers = listOf(
                AgentRequestedMember("codex", "Codex", 1, "implement the feature"),
                AgentRequestedMember("codex", "Codex", 2, "run independent tests"),
                AgentRequestedMember("claude", "Claude", 1, "review the design")
            )
        )

        val action = compiled.actions.single()
        val spec = requireNotNull(
            AgentTeamDispatchSpecCodec.decode(action.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty())
        )
        assertEquals("user_mention", action.parameters["agent_selection_source"])
        assertEquals("codex:mention-1", spec.definition.primaryMemberId)
        assertEquals(
            listOf("codex:mention-1", "codex:mention-2", "claude:mention-1"),
            spec.definition.members.map(AgentTeamMember::memberId)
        )
        assertEquals(
            setOf("codex:mention-2", "claude:mention-1"),
            spec.definition.members.first().dependsOnAgentIds
        )
        assertEquals(
            "review the design",
            spec.definition.members.single { it.agentId == "claude" }.context["_signalasi_role_hint"]
        )
        assertEquals(1, spec.definition.members.count { it.deliveryMode == AgentDeliveryMode.RESPOND })
        assertTrue(compiled.validation.valid)
    }

    @Test
    fun oneUserMentionLocksTheTaskToThatAgentWithoutCreatingATeam() {
        val codex = target("codex", AgentConnectorKind.AGENT, AgentCapability.CODE)
        val original = plan(agentAction("fallback", "codex"))

        val compiled = AgentTeamPlanCompiler.compile(
            plan = original,
            targets = listOf(codex),
            enabled = true,
            registrations = targetRegistrations(listOf(codex)),
            requestedMembers = listOf(AgentRequestedMember("codex", "Codex"))
        )

        assertEquals("codex", compiled.actions.single().parameters["connector_id"])
        assertEquals("true", compiled.actions.single().parameters["manual_target_locked"])
        assertNull(compiled.actions.single().parameters[AGENT_TEAM_SPEC_PARAMETER])
        assertTrue(compiled.validation.valid)
    }

    @Test
    fun userMentionsCanBeCombinedWithAutomaticTeamExpansion() {
        val codex = target("codex", AgentConnectorKind.AGENT, AgentCapability.CODE)
        val claude = target("claude", AgentConnectorKind.AGENT, AgentCapability.REASONING)
        val deepseek = target("deepseek", AgentConnectorKind.AGENT, AgentCapability.CODE).copy(
            capabilities = listOf(AgentCapability.CODE, AgentCapability.REASONING)
        )
        val original = plan(agentAction("fallback", "codex")).copy(
            goal = "@Codex @Claude implement and independently verify this change, then automatically find another Agent"
        )

        val compiled = AgentTeamPlanCompiler.compile(
            plan = original,
            targets = listOf(codex, claude, deepseek),
            enabled = true,
            registrations = targetRegistrations(listOf(codex, claude, deepseek)),
            requestedMembers = listOf(
                AgentRequestedMember("codex", "Codex"),
                AgentRequestedMember("claude", "Claude")
            )
        )

        val spec = requireNotNull(AgentTeamDispatchSpecCodec.decode(
            compiled.actions.single().parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty()
        ))
        assertTrue(spec.definition.members.any { it.agentId == "codex" })
        assertTrue(spec.definition.members.any { it.agentId == "claude" })
        assertTrue(spec.definition.members.any { it.agentId == "deepseek" })
        assertEquals(1, spec.definition.members.count { it.deliveryMode == AgentDeliveryMode.RESPOND })
    }

    @Test
    fun repeatedUserMentionFailsWhenTheAgentHasInsufficientCapacity() {
        val codex = target("codex", AgentConnectorKind.AGENT, AgentCapability.CODE)

        val failure = runCatching {
            AgentTeamPlanCompiler.compile(
                plan = plan(agentAction("fallback", "codex")),
                targets = listOf(codex),
                enabled = true,
                registrations = targetRegistrations(listOf(codex)),
                requestedMembers = listOf(
                    AgentRequestedMember("codex", "Codex", 1),
                    AgentRequestedMember("codex", "Codex", 2)
                )
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalArgumentException)
        assertTrue(failure?.message.orEmpty().contains("available Run slots"))
    }

    @Test
    fun legacyDispatchWithoutInstanceFieldsFallsBackToAgentIds() {
        val source = AgentTeamDispatchSpec(
            AgentTeamDefinition(
                teamId = "legacy-team",
                primaryAgentId = "lead",
                members = listOf(
                    AgentTeamMember("researcher", AgentDeliveryMode.OBSERVE),
                    AgentTeamMember("lead", AgentDeliveryMode.RESPOND)
                )
            ),
            supervisorRunId = "legacy-run"
        )
        val legacy = JSONObject(AgentTeamDispatchSpecCodec.encode(source)).apply {
            remove("primary_instance_id")
            val members = getJSONArray("members")
            for (index in 0 until members.length()) {
                members.getJSONObject(index).remove("instance_id")
            }
        }

        val decoded = requireNotNull(AgentTeamDispatchSpecCodec.decode(legacy.toString()))

        assertEquals("lead", decoded.definition.primaryMemberId)
        assertEquals(
            listOf("researcher", "lead"),
            decoded.definition.members.map(AgentTeamMember::memberId)
        )
    }

    @Test
    fun retryCreatesANewPersistableTeamAttempt() {
        val compiled = AgentTeamPlanCompiler.compile(
            plan = plan(
                agentAction("research", "researcher"),
                agentAction("synthesis", "lead", dependsOn = listOf("research"))
            ),
            targets = targets(),
            enabled = true
        )
        val original = compiled.actions.single()

        val retry = original.rekeyAgentTeamForRetry()
        val originalSpec = requireNotNull(
            AgentTeamDispatchSpecCodec.decode(original.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty())
        )
        val retrySpec = requireNotNull(
            AgentTeamDispatchSpecCodec.decode(retry.parameters[AGENT_TEAM_SPEC_PARAMETER].orEmpty())
        )

        assertTrue(originalSpec.definition.teamId != retrySpec.definition.teamId)
        assertTrue(originalSpec.supervisorRunId != retrySpec.supervisorRunId)
        assertTrue(originalSpec.sourceMessageId != retrySpec.sourceMessageId)
        assertEquals(retrySpec.supervisorRunId, retry.parameters[AGENT_TEAM_RUN_PARAMETER])
        assertEquals(retrySpec.sourceMessageId.toString(), retry.parameters[AGENT_TEAM_SOURCE_PARAMETER])
    }

    private fun plan(vararg actions: AgentAction): AgentPlan {
        val draft = AgentPlan(
            goal = "Research and synthesize a verified answer",
            screen = ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent"),
            steps = emptyList(),
            actions = actions.toList(),
            route = AgentRoute(kind = AgentRouteKind.DESKTOP_AGENT)
        )
        return draft.copy(validation = AgentPlanValidator.validate(draft))
    }

    private fun agentAction(
        id: String,
        connectorId: String,
        dependsOn: List<String> = emptyList(),
        outputSources: List<String> = emptyList()
    ): AgentAction = connectorAction(id, connectorId, dependsOn, outputSources)

    private fun connectorAction(
        id: String,
        connectorId: String,
        dependsOn: List<String> = emptyList(),
        outputSources: List<String> = emptyList()
    ) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_CONNECTOR,
        target = connectorId,
        risk = AgentRisk.MEDIUM,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "Run $id",
        parameters = mapOf(
            "connector_id" to connectorId,
            "prompt" to "Complete $id",
            "node_ref" to id,
            "depends_on" to dependsOn.joinToString(","),
            "use_outputs_from" to outputSources.joinToString(","),
            "_signalasi_conversation_id" to "conversation",
            "_signalasi_turn_id" to "turn"
        )
    )

    private fun targets(): List<AgentCallableTarget> = listOf(
        target("researcher", AgentConnectorKind.AGENT, AgentCapability.RESEARCH),
        target("reviewer", AgentConnectorKind.AGENT, AgentCapability.RESEARCH),
        target("lead", AgentConnectorKind.AGENT, AgentCapability.REASONING)
    )

    private fun target(
        id: String,
        kind: AgentConnectorKind,
        capability: AgentCapability = AgentCapability.CHAT
    ) = AgentCallableTarget(
        id = id,
        title = id,
        kind = kind,
        status = AgentConnectorStatus.AVAILABLE,
        capabilities = listOf(capability)
    )

    private fun targetRegistrations(targets: List<AgentCallableTarget>): List<AgentRegistration> =
        object : AgentConnectorRegistry {
            override fun availableTargets(): List<AgentCallableTarget> = targets
        }.registrations()

    private fun AgentAction.withAgentKnowledge(value: String): AgentAction = copy(
        parameters = parameters + ("_signalasi_agent_knowledge_context" to value)
    )
}
