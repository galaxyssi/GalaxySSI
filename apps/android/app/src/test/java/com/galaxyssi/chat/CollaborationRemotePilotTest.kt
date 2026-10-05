package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationRemotePilotTest {
    private fun input() = JSONObject().put("format", "galaxyssi.remote-collaboration-pilot.v1").put("pilot_id", "pilot-1")
        .put("target_id", "desktop:codex").put("model_id", "gpt-6-astra").put("reasoning_effort", "xhigh")
        .put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE).put("trial_timeout_ms", 180_000)
        .put("slots", JSONArray(listOf("single", "team").map { JSONObject().put("id", it).put("case_id", "case-1")
            .put("arm", it).put("prompt", "Compare the supplied source records and return the requested table.") }))
    private fun plan() = CollaborationRemotePilotPlan.from(input(), 6)
    private fun execution(plan: CollaborationRemotePilotPlan, node: String = "draft", arm: Int = 0): AgentTeamMemberExecutionContext {
        val member = plan.definition(plan.slots[arm], "group", "run").members.single { it.memberId == node }
        return AgentTeamMemberExecutionContext(member, AgentRunRequest("group", "turn", "task", runId = "owner-$node",
            parentRunId = "run", goal = plan.slots[arm].prompt, idempotencyKey = "run:$node"),
            AgentSubagentContextHandoff("unrelated hidden memory", emptyList(), 0, 60_000, false), 0, AgentSubagentProvenance())
    }
    private fun action(context: AgentTeamMemberExecutionContext) = AgentAction("action", AgentActionKind.CALL_CONNECTOR,
        "Codex", AgentRisk.LOW, AgentActionStatus.RUNNING, "fixture", parameters = mapOf(
            "connector_id" to "desktop:codex", "agent_model_id" to "gpt-6-astra", "manual_model_id" to "gpt-6-astra",
            "agent_reasoning_effort" to "xhigh", "manual_target_locked" to "true", MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true",
            "agent_instance_id" to context.member.memberId, "_galaxyssi_conversation_id" to "group", "_galaxyssi_turn_id" to "turn",
            "_galaxyssi_task_id" to "task", "idempotency_key" to context.request.idempotencyKey, "prompt" to "legacy prompt"))
    private fun guard(plan: CollaborationRemotePilotPlan, now: () -> Long = { 1 }, persist: (JSONObject) -> Unit = {}) =
        CollaborationRemotePilotDispatch(plan, plan.definition(plan.slots.first(), "group", "run"), "group", "run", "turn", 100, now, persist)

    @Test fun modelAndEffortComeFromExplicitAppSelectionNotAnAstraDefault() {
        for ((model, effort) in listOf("gpt-6-astra" to "xhigh", "test-future-model" to "high")) {
            val plan = CollaborationRemotePilotPlan.from(input().put("model_id", model).put("reasoning_effort", effort), 6)
            val selected = AgentModelSelection(AgentModelSelectionMode.MANUAL, plan.targetId, model,
                reasoningEffort = AgentModelReasoningEffort.fromWireValue(effort))
            plan.requireAppSelection(selected)
            plan.slots.flatMap { plan.definition(it, "group", "run").members }.forEach {
                assertEquals(model, it.context["collaboration_model_id"])
                assertEquals(effort, it.context[CollaborationReasoningSelection.KEY])
            }
            for (changed in listOf(selected.copy(mode = AgentModelSelectionMode.AUTO), selected.copy(targetId = "other:codex"),
                selected.copy(modelId = "different-model"), selected.copy(reasoningEffort = AgentModelReasoningEffort.LOW))) {
                assertThrows(IllegalArgumentException::class.java) { plan.requireAppSelection(changed) }
            }
        }
    }

    @Test fun sameTasksRolesControlsAndOpportunitiesForBothArms() {
        val plan = plan()
        assertEquals(6, plan.maximumDispatches)
        val graphs = plan.slots.map { plan.definition(it, "group", "run") }
        assertEquals(graphs[0].members.map { it.objective }, graphs[1].members.map { it.objective })
        assertEquals(graphs[0].members.map { it.role }, graphs[1].members.map { it.role })
        assertEquals(listOf("draft", "review", "final"), graphs[0].members.map { it.memberId })
        graphs.forEachIndexed { index, graph ->
            assertEquals(if (index == 0) 1 else 2, graph.members.map { it.context[CollaborationResearchWorkflow.PERSON] }.distinct().size)
            assertTrue(graph.members.all { it.agentId == "desktop:codex" && it.context["collaboration_model_id"] == "gpt-6-astra" &&
                it.context[CollaborationReasoningSelection.KEY] == "xhigh" && CollaborationResearchWorkflow.stage(it) == null })
            assertEquals(setOf("draft", "review"), graph.members.last().dependsOnAgentIds)
        }
    }

    @Test fun protocolCannotClaimClosedBookOrHideUnequalInputs() {
        val changes: List<(JSONObject) -> Unit> = listOf(
            { it.put("tool_scope", "closed_book") }, { it.put("answer_key", "private") },
            { it.getJSONArray("slots").getJSONObject(0).put("rubric", "private") },
            { it.getJSONArray("slots").remove(1) },
            { it.getJSONArray("slots").getJSONObject(1).put("prompt", "different") },
            { it.getJSONArray("slots").getJSONObject(1).put("arm", "single") },
            { it.getJSONArray("slots").getJSONObject(1).put("id", "single") },
            { it.put("pilot_id", "../escape") }, { it.put("target_id", "cloud") },
            { it.put("model_id", "auto") }, { it.put("reasoning_effort", "auto") }
        )
        changes.forEach { change -> assertThrows(IllegalArgumentException::class.java) {
            CollaborationRemotePilotPlan.from(input().also(change), 6)
        } }
    }

    @Test fun noCoercionOverBudgetOrSilentInputTruncation() {
        for (cap in listOf(0, 5)) assertThrows(IllegalArgumentException::class.java) { CollaborationRemotePilotPlan.from(input(), cap) }
        for (time in listOf<Any>(0, 900_001, "180000", true)) assertThrows(RuntimeException::class.java) {
            CollaborationRemotePilotPlan.from(input().put("trial_timeout_ms", time), 6)
        }
        for (key in listOf("model_id", "reasoning_effort", "pilot_id", "target_id")) assertThrows(RuntimeException::class.java) {
            CollaborationRemotePilotPlan.from(input().put(key, 123), 6)
        }
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationRemotePilotPlan.from(input().also { repeat(2) { i ->
                it.getJSONArray("slots").getJSONObject(i).put("prompt", "x".repeat(12_001)) } }, 6)
        }
    }

    @Test fun promptPreservesOriginalAndFullDependenciesNotAmbientMemory() {
        val plan = plan()
        val ctx = execution(plan, "review")
        val dependency = AgentSubagentDependencyHandoff("draft", AgentSubagentStatus.SUCCEEDED, "source evidence", false,
            provenance = AgentSubagentProvenance())
        val prompt = plan.prompt(ctx.copy(handoff = ctx.handoff.copy(dependencies = listOf(dependency))))
        assertTrue(prompt.contains(plan.slots.first().prompt) && prompt.contains("source evidence"))
        assertFalse(prompt.contains("unrelated hidden memory"))
        assertTrue(prompt.contains("not a sandbox"))
        assertThrows(IllegalStateException::class.java) { plan.prompt(ctx.copy(handoff = ctx.handoff.copy(truncated = true))) }
        assertThrows(IllegalStateException::class.java) { plan.prompt(ctx.copy(handoff = ctx.handoff.copy(
            dependencies = listOf(dependency.copy(outputTruncated = true))))) }
        assertThrows(IllegalStateException::class.java) { plan.prompt(ctx.copy(handoff = ctx.handoff.copy(
            dependencies = listOf(dependency.copy(output = "x".repeat(60_001)))))) }
    }

    @Test fun exactControlsAreReservedBeforeDelegateExecutionWithoutPromptInLedger() {
        val plan = plan()
        val ctx = execution(plan)
        val records = mutableListOf<JSONObject>()
        val guard = guard(plan, persist = records::add)
        guard.prepare(ctx)
        val adjusted = guard.admit(action(ctx))
        assertEquals(plan.prompt(ctx), adjusted.parameters["prompt"])
        assertEquals(1, records.size)
        assertEquals("xhigh", records.single().getString("requested_reasoning_effort"))
        assertEquals(CollaborationRemotePilotDispatch.sha256(plan.prompt(ctx).toByteArray()), records.single().getString("prepared_prompt_sha256"))
        assertFalse(records.single().toString().contains(plan.slots.first().prompt))
        assertThrows(IllegalStateException::class.java) { guard.admit(action(ctx)) }
        assertThrows(IllegalStateException::class.java) { guard.prepare(ctx) }
    }

    @Test fun everyRoutingControlRejectsTamperingBeforeReservation() {
        val plan = plan()
        val ctx = execution(plan)
        for (key in action(ctx).parameters.keys - "prompt") {
            val records = mutableListOf<JSONObject>()
            val guard = guard(plan, persist = records::add)
            guard.prepare(ctx)
            assertThrows(RuntimeException::class.java) { guard.admit(action(ctx).copy(parameters = action(ctx).parameters + (key to "changed"))) }
            assertTrue(records.isEmpty())
        }
        val guard = guard(plan)
        guard.prepare(ctx)
        assertThrows(IllegalStateException::class.java) { guard.admit(action(ctx).copy(kind = AgentActionKind.READ_SCREEN)) }
    }

    @Test fun crossRunOrAlteredMemberIsRejected() {
        val plan = plan()
        val ctx = execution(plan)
        val changed = listOf(ctx.copy(member = ctx.member.copy(objective = "changed")),
            ctx.copy(request = ctx.request.copy(parentRunId = "other")), ctx.copy(request = ctx.request.copy(conversationId = "other")),
            ctx.copy(request = ctx.request.copy(messageId = "other")))
        changed.forEach { assertThrows(IllegalStateException::class.java) { guard(plan).prepare(it) } }
    }

    @Test fun deadlineIsCheckedAgainImmediatelyBeforeDispatch() {
        val plan = plan()
        var time = 1L
        val guard = guard(plan, now = { time })
        val ctx = execution(plan)
        guard.prepare(ctx)
        time = 100
        assertThrows(IllegalStateException::class.java) { guard.admit(action(ctx)) }
        assertThrows(IllegalStateException::class.java) { guard(plan, now = { 100 }).prepare(ctx) }
    }

    @Test fun closedGuardAndUnpreparedDispatchCannotExecute() {
        val plan = plan()
        val ctx = execution(plan)
        assertThrows(IllegalArgumentException::class.java) { guard(plan).admit(action(ctx)) }
        val guard = guard(plan)
        guard.prepare(ctx)
        guard.close()
        assertThrows(IllegalStateException::class.java) { guard.admit(action(ctx)) }
        assertThrows(IllegalStateException::class.java) { guard.prepare(ctx) }
    }

    @Test fun failedJournalWriteConsumesReservationAndNeverDispatches() {
        val plan = plan()
        val ctx = execution(plan)
        val guard = guard(plan, persist = { throw java.io.IOException("fixture disk full") })
        guard.prepare(ctx)
        assertThrows(java.io.IOException::class.java) { guard.admit(action(ctx)) }
        assertThrows(IllegalStateException::class.java) { guard.admit(action(ctx)) }
    }

    @Test fun bothActualGraphsRunThreeSyntheticNodesAndKeepIdentityTreatment() = runBlocking {
        val plan = plan()
        for (slot in plan.slots) {
            val graph = plan.definition(slot, "group", "run")
            val records = mutableListOf<JSONObject>()
            val guard = CollaborationRemotePilotDispatch(plan, graph, "group", "run", "turn", Long.MAX_VALUE, { 1 }, records::add)
            val runtime = AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore(), AgentSubagentLimits(maxConcurrency = 1,
                maxContextChars = 60_000, maxOutputChars = 24_000))
            try {
                val result = runtime.start(graph, AgentRunRequest("group", "turn", "task", runId = "run", goal = slot.prompt,
                    idempotencyKey = "run"), AgentTeamMemberWorker { ctx ->
                    guard.prepare(ctx)
                    guard.admit(action(ctx))
                    AgentSubagentOutput("synthetic-${ctx.member.memberId}")
                }).await()
                assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
                assertEquals(listOf("draft", "review", "final"), records.map { it.getString("node_id") })
                assertEquals(if (slot.arm == "single") 1 else 2, records.map { it.getString("person_id") }.distinct().size)
            } finally { guard.close(); runtime.close() }
        }
    }
}
