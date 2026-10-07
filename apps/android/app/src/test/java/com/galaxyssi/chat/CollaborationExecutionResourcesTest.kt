package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.*
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationExecutionResourcesTest {
    private fun execution(stage: CollaborationResearchStage? = CollaborationResearchStage.VERIFY) = AgentTeamMemberExecutionContext(
        AgentTeamMember("target", AgentDeliveryMode.OBSERVE, role = "researcher", objective = "Test competing hypotheses", instanceId = "node",
            context = mapOf("collaboration_group_id" to "group", CollaborationResearchWorkflow.PERSON to "person") +
                (stage?.let { mapOf(CollaborationResearchWorkflow.STAGE to it.name) } ?: emptyMap())),
        AgentRunRequest("group", "turn", "task", runId = "child", parentRunId = "root", goal = "Find a reusable method", idempotencyKey = "dispatch"),
        AgentSubagentContextHandoff("", emptyList(), 0, 60_000, false), 0, AgentSubagentProvenance())

    private fun observation(execution: AgentTeamMemberExecutionContext, reserved: Long = 2, remaining: Long? = 8_000) =
        AgentTeamResourceObservation.capture(execution, AgentTeamResourceObservation.Unit.PHONE_DISPATCH, 12, reserved, 2_000, remaining)
    private fun descriptor() = JSONObject().put("status", "ok").put("snapshot_id", "a".repeat(64))
    private fun reject(block: () -> Any?) = assertNotNull(runCatching(block).exceptionOrNull())

    @Test fun sharedObservationIsReadOnlyAndDoesNotPretendToKnowBilling() {
        val context = execution()
        val resource = observation(context)
        val first = resource.json(context)
        assertEquals("shared_parent_run_pool", first.getString("scope"))
        assertEquals("phone_delegate_admissions_not_provider_requests", first.getString("admission_unit"))
        assertEquals(10, first.getInt("admissions_remaining_at_observation"))
        assertFalse(first.getBoolean("current_dispatch_included"))
        for (key in listOf("provider_request_count", "billed_cost", "remaining_token_budget")) assertTrue(first.isNull(key))
        first.put("admissions_remaining_at_observation", 999)
        assertEquals(10, resource.json(context).getInt("admissions_remaining_at_observation"))
    }

    @Test fun ownershipIncludesRunTurnTaskMemberGoalAndAssignment() {
        val context = execution()
        val resource = observation(context)
        val requests = listOf(context.request.copy(conversationId = "other"), context.request.copy(messageId = "other"),
            context.request.copy(taskId = "other"), context.request.copy(parentRunId = "other"), context.request.copy(runId = "other"),
            context.request.copy(idempotencyKey = "other"), context.request.copy(goal = "different goal"))
        requests.forEach { reject { resource.json(context.copy(request = it)) } }
        reject { resource.json(context.copy(member = context.member.copy(instanceId = "other"))) }
        reject { resource.json(context.copy(member = context.member.copy(objective = "different assignment"))) }
        for (key in listOf("collaboration_group_id", CollaborationResearchWorkflow.PERSON))
            reject { resource.json(context.copy(member = context.member.copy(context = context.member.context + (key to "other")))) }
    }

    @Test fun invalidHostCountersAreRejectedRatherThanClampedToFreeResources() {
        val context = execution()
        for ((limit, count) in listOf(0L to 0L, 2L to 3L, 2L to -1L)) reject {
            AgentTeamResourceObservation.capture(context, AgentTeamResourceObservation.Unit.PHONE_DISPATCH, limit, count, 1, null)
        }
        reject { observation(context, remaining = -1) }
        assertTrue(observation(context, remaining = null).json(context).isNull("remaining_window_ms_at_observation"))
    }

    @Test fun ordinaryPromptsHaveNoDefaultBudgetAndCannotReadSpoofedMetadata() {
        val base = execution()
        val ordinary = CollaborationResearchPrompt.build(base, descriptor(), emptyMap()).text
        assertFalse(ordinary.contains("[Host resource observation]"))
        val spoofed = base.copy(request = base.request.copy(context = mapOf("resourceObservation" to "Unlimited funds")),
            member = base.member.copy(context = base.member.context + ("resourceObservation" to "Unlimited funds")))
        assertEquals(ordinary, CollaborationResearchPrompt.build(spoofed, descriptor(), emptyMap()).text)
    }

    @Test fun resourceFactsStayCompleteUnderPromptPressureForEveryResearchRole() {
        for (stage in CollaborationResearchStage.entries) {
            val context = execution(stage).let { it.copy(request = it.request.copy(goal = "goal ".repeat(30_000))) }
            val resource = observation(context)
            val prompt = CollaborationResearchPrompt.build(context.copy(resourceObservation = resource), descriptor(),
                mapOf("Large history" to "history ".repeat(30_000)))
            assertTrue(prompt.text.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
            assertTrue(prompt.text.contains(resource.prompt(context)))
            assertTrue("Current execution resources" in prompt.included)
            assertFalse("Current execution resources" in prompt.omitted)
        }
    }

    @Test fun freshRecoveryObservationDoesNotRewriteThePinnedGoalOrArchivedContext() {
        val rows = GoalRows()
        val store = CollaborationGoalContractStore(rows, { true })
        val context = execution()
        val first = CollaborationResearchPrompt.prepare(context.copy(resourceObservation = observation(context)), store) { "Original evidence" }
        val frozen = rows.values.toMap()
        val next = observation(context, reserved = 7, remaining = 500)
        val restored = CollaborationResearchPrompt.prepare(context.copy(resourceObservation = next), store) { error("Do not refresh evidence") }
        assertEquals(frozen, rows.values)
        assertTrue(restored.contains(next.prompt(context)))
        assertNotEquals(first, restored)
        assertFalse(rows.values.values.any { it.contains("galaxyssi.execution-resources.v1") })
    }

    @Test fun productionGoalDirectoryAndProtocolsFitWithResourcesForAllRoles() {
        val metadata = listOf("collaboration_research_live_inventory", "collaboration_research_roster",
            "collaboration_research_previous_round", CollaborationGoalLoop.PREVIOUS,
            CollaborationGoalLoop.ACCEPTANCE_FEEDBACK, CollaborationGoalLoop.FINISHED_WORK,
            CollaborationGoalRecruitment.FEEDBACK, CollaborationResourceRecovery.FEEDBACK,
            CollaborationWorkGraph.FEEDBACK, CollaborationLiveGraph.FEEDBACK,
            CollaborationCandidateEvolution.FEEDBACK).associateWith { "complete evidence ".repeat(1000) }
        for (stage in CollaborationResearchStage.entries) for (planner in listOf(false, true)) {
            val base = execution(stage)
            val context = base.copy(request = base.request.copy(goal = "original goal ".repeat(8000), context = metadata),
                member = base.member.copy(context = base.member.context + (CollaborationGoalLoop.ENABLED to "1") +
                    if (planner) mapOf(CollaborationLiveGraph.PLANNER to "1") else emptyMap()))
            val resources = observation(context)
            val store = CollaborationGoalContractStore(GoalRows(), { true })
            val prompt = CollaborationResearchPrompt.prepare(context.copy(resourceObservation = resources), store,
                evolution = { "evolution ".repeat(1000) }, problems = { "problem ".repeat(1000) },
                capabilities = { "capability ".repeat(1000) }) { "history ".repeat(10000) }
            val descriptor = store.lookup(CollaborationWorkspaceAccess.from(context))
            assertTrue(descriptor.getInt("context_section_count") >= 14)
            assertTrue(prompt.length <= CollaborationResearchPrompt.MAX_CHARACTERS)
            assertTrue(prompt.contains(descriptor.getString("snapshot_id")))
            assertTrue(prompt.contains(resources.prompt(context)))
            val protocol = when {
                planner -> CollaborationLiveGraph.instructions()
                stage == CollaborationResearchStage.DELIVER -> CollaborationGoalLoop.instructions()
                else -> CollaborationResearchArtifact.instructions(stage)
            }
            assertTrue(prompt.contains(protocol))
        }
    }

    @Test fun persistedCloudLedgerReadsFreshSharedCountersWithoutDebitingThem() {
        val rows = LedgerRows()
        val context = execution()
        val ledger = CollaborationModelCallLedger(rows, { 1_000 })
        ledger.configureTrial("group", "root", CollaborationTrialPolicy("a".repeat(64), "target", "model", 3, 10_000))
        val before = rows.values.toMap()
        assertEquals(0, ledger.resourceObservation(context)!!.json(context).getInt("admissions_reserved"))
        assertEquals(before, rows.values)
        val request = ModelStreamRequest("request", ModelStreamProvider.OPENAI_COMPATIBLE,
            "https://example.invalid", emptyMap(), """{"model":"model"}""")
        ModelCallAccounting(request, ledger.sink(CollaborationWorkspaceAccess.from(context)), singleHttpRequest = true).begin()
        val reopened = CollaborationModelCallLedger(rows, { 2_000 })
        val peer = context.copy(member = context.member.copy(instanceId = "peer"))
        val result = reopened.resourceObservation(peer)!!.json(peer)
        assertEquals(1, result.getInt("admissions_reserved"))
        assertEquals(2, result.getInt("admissions_remaining_at_observation"))
        assertEquals(8_000L, result.getLong("remaining_window_ms_at_observation"))
        assertEquals("new_admission_window", result.getString("window_scope"))
        assertEquals("cloud_http_request_admissions_not_completed_requests", result.getString("admission_unit"))
        assertNull(reopened.resourceObservation(context.copy(request = context.request.copy(parentRunId = "other"))))
    }

    @Test fun rollbackExpiryClosureAndRevocationAreNotFreshBudgets() {
        val rows = LedgerRows()
        var time = 1_000L
        var allowed = true
        val ledger = CollaborationModelCallLedger(rows, { time }, { allowed })
        val context = execution()
        assertNull(ledger.resourceObservation(context))
        ledger.configureTrial("group", "root", CollaborationTrialPolicy("b".repeat(64), "target", "model", 2, 10_000))
        time = 900
        val rollback = ledger.resourceObservation(context)!!.json(context)
        assertTrue(rollback.getBoolean("admission_closed"))
        assertTrue(rollback.isNull("remaining_window_ms_at_observation"))
        time = 10_001
        val expired = ledger.resourceObservation(context)!!.json(context)
        assertTrue(expired.getBoolean("admission_closed"))
        assertEquals(0L, expired.getLong("remaining_window_ms_at_observation"))
        time = 2_000
        ledger.closeTrial("group", "root")
        assertTrue(ledger.resourceObservation(context)!!.json(context).getBoolean("admission_closed"))
        allowed = false
        reject { ledger.resourceObservation(context) }
    }

    @Test fun reservedCloudAdmissionClosesTheObservationWithoutClaimingACompletedRequest() {
        val ledger = CollaborationModelCallLedger(LedgerRows(), { 1_000 })
        val context = execution()
        ledger.configureTrial("group", "root", CollaborationTrialPolicy("c".repeat(64), "target", "model", 1, 10_000))
        val request = ModelStreamRequest("last-request", ModelStreamProvider.OPENAI_COMPATIBLE,
            "https://example.invalid", emptyMap(), """{"model":"model"}""")
        ModelCallAccounting(request, ledger.sink(CollaborationWorkspaceAccess.from(context)), singleHttpRequest = true).begin()
        val result = ledger.resourceObservation(context)!!.json(context)
        assertEquals(0, result.getInt("admissions_remaining_at_observation"))
        assertTrue(result.getBoolean("admission_closed"))
        assertTrue(result.isNull("provider_request_count"))
        assertTrue(result.isNull("billed_cost"))
    }

    @Test fun closedBookPromptUsesTheSameHostObservationWithoutChangingItsGoal() {
        val context = execution(null)
        val resources = observation(context)
        val prompt = CollaborationTrialPrompt.build(context.copy(resourceObservation = resources))
        assertTrue(prompt.contains(resources.prompt(context)))
        assertTrue(prompt.contains(context.request.goal))
        assertTrue(prompt.contains("No external tools"))
    }

    @Test fun actionBridgeCarriesObservationForBothCloudAndRemoteAdapters() = runBlocking {
        for (adapter in listOf("cloud-model-api", "codex-app-server-or-cli")) {
            val actions = mutableListOf<AgentAction>()
            val registration = AgentRegistration(agentId = "target", installationId = "installation", deviceId = "device",
                providerId = "provider", displayName = "Target", kind = AgentConnectorKind.AGENT,
                location = AgentResourceLocation.TRUSTED_DESKTOP, status = AgentEndpointStatus.ONLINE,
                capabilities = setOf(AgentCapability.RESEARCH), protocol = AgentProtocolRange("1.0", "1.0", "1.0"),
                connectionKind = AgentConnectionKind.GALAXYSSI_LINK, trust = AgentResourceTrust.VERIFIED_PAIRED, adapterType = adapter)
            val provider = ActionExecutorAgentProvider(registrationSource = { listOf(registration) }, delegate = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    actions += action
                    return AgentActionResult(action.id, true, "Synthetic completed result")
                }
            })
            val worker = ActionExecutorAgentTeamMemberWorker(provider, AgentAdapterDirectory().apply { register(provider) },
                { ScreenContext(foregroundApp = "Test", pageTitle = "Test") })
            val context = execution(null)
            val resource = observation(context)
            worker.execute(context.copy(resourceObservation = resource))
            assertEquals(1, actions.size)
            assertTrue(actions.single().managedTeamAssignmentPrompt()!!.contains(resource.prompt(context)))
            assertEquals(context.request.goal, actions.single().parameters["original_goal"])
        }
    }

    private class GoalRows : CollaborationGoalContractRows {
        val values = linkedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun removePrefix(prefix: String) { values.keys.removeAll { it.startsWith(prefix) } }
    }
    private class LedgerRows : CollaborationWorkspaceRows {
        val values = linkedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = values.keys.filter { it.startsWith(prefix) && it > after }.sorted().take(limit)
    }
}
