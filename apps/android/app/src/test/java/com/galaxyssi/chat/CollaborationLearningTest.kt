package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationLearningTest {
    private class Rows : CollaborationWorkspaceRows {
        val values = sortedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = values.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private class Fixture {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        fun access(round: Long = 3) = CollaborationWorkspaceAccess("group", "run", "turn", round, "lead-node-$round", "lead")
        fun publish(id: String, kind: String, spec: JSONObject, round: Long): JSONObject {
            val receipt = workspace.publish(access(round), JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
                .put("summary", "Local learning fixture").put("candidates", JSONArray()).put("findings", JSONArray())
                .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", kind).put("title", id)
                    .put("body", JSONObject().put("content", "Fixture only").put(kind, spec)))).toString(), round * 10)
            return if (receipt.optString("status") == "recorded") receipt.getJSONArray("revisions").getJSONObject(0) else receipt
        }
        val gap = publish("gap", "capability_gap", JSONObject("""{"category":"method","symptom":"Weak source comparison",
            "needed_capability":"Cross-check claims","chosen_option":"small","rationale":"Start with discriminating evidence",
            "learning_options":[{"id":"small","action":"Small test","expected_gain":"Find weakness","cost":"unknown",
            "goal_relevance":"Evidence quality","verification":"Original test"},{"id":"broad","action":"Broader test",
            "expected_gain":"Transfer","cost":"unknown","goal_relevance":"Evidence quality","verification":"Held-out test"},
            {"id":"later","action":"Extra test","expected_gain":"More coverage","cost":"unknown",
            "goal_relevance":"Optional","verification":"Later test"}]}"""), 1)
        fun option(id: String, priority: Int, decision: String = "select") = JSONObject().put("id", id).put("gap", gap)
            .put("gap_option", id).put("priority", priority).put("decision", decision).put("member", "peer")
            .put("stage", "VERIFY").put("assignment", "Run $id fixture and preserve observed results")
            .put("current_goal_value", "Reduce uncertainty on source quality").put("future_transfer_value", "Check future reuse independently")
            .put("information_gain", "Distinguish two methods").put("uncertainty", "Learning gain unknown")
            .put("tradeoff", "Small test before large sweep").put("verification", "Original probe and independent experiment")
            .put("reconsider_when", "New probe evidence")
            .put("resource_estimates", JSONArray().put(JSONObject().put("unit", "elapsed_ms").put("status", "estimated")
                .put("value", 100).put("basis", "Local fixture estimate"))
                .put(JSONObject().put("unit", "cost_micros").put("status", "unknown").put("basis", "No price available")))
        fun spec() = JSONObject().put("goal_alignment", "Improve evidence comparison").put("resource_reasoning", "One executor slot")
            .put("selection_reason", "Discriminating test first").put("reconsider_when", "Observe outcome")
            .put("options", JSONArray().put(option("broad", 2)).put(option("small", 1)).put(option("later", 3, "defer")))
        fun agenda(change: (JSONObject) -> Unit = {}) = publish("agenda", CollaborationLearningAgenda.KIND, spec().apply(change), 2)
        fun work(ref: JSONObject, id: String) = option(id, 1).let {
            JSONObject().put("id", "learn-$id").put("member", "peer").put("stage", "VERIFY").put("assignment", it.getString("assignment"))
                .put("learning", JSONObject().put("agenda", ref).put("option_id", id))
        }
        fun record(): AgentTeamExecutionRecord {
            val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
                AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "peer")), "Improve evidence comparison").map {
                it.copy(context = it.context + mapOf("collaboration_group_id" to "group", CollaborationLiveGraph.ENABLED to "1"))
            }
            return AgentTeamExecutionRecord(AgentTeamDefinition("team", "fixture", members, primaryInstanceId = "lead"),
                AgentRunRequest("group", "turn", "task", runId = "run", goal = "Improve evidence comparison",
                    context = mapOf(CollaborationGoalLoop.ROUND to "2")))
        }
        fun plan(ref: JSONObject = agenda(), items: List<JSONObject> = listOf(work(ref, "broad"), work(ref, "small")),
                 record: AgentTeamExecutionRecord = record()) = CollaborationLearningWork.plan(record, items, { workspace }, access())
        fun report(items: List<JSONObject>) = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Compare learning alternatives")
            .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "quality")
                .put("requirement", "Improve evidence comparison").put("status", "open").put("evidence", JSONArray())))
            .put("work", JSONArray(items)).put("blockers", JSONArray())
        fun finished(record: AgentTeamExecutionRecord, child: String, output: String, terminal: Boolean = false): AgentTeamExecutionRecord {
            val seq = record.events.size + 1L
            val result = AgentSubagentChildResult("run", child, "run", 1, AgentSubagentStatus.SUCCEEDED, output, startedAtMillis = 100, completedAtMillis = 300)
            val event = AgentSubagentEvent(seq, "run", child, AgentSubagentEventKinds.CHILD_SUCCEEDED,
                childStatus = AgentSubagentStatus.SUCCEEDED, result = result)
            return record.copy(events = record.events + event + if (terminal) listOf(AgentSubagentEvent(seq + 1, "run",
                kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED)) else emptyList())
        }
    }

    @Test fun preservesAlternativesAndUncertaintyWithoutLearningOrSpendingClaims() {
        val f = Fixture(); val agenda = f.agenda()
        val host = agenda.getJSONObject("host_evolution")
        assertEquals(2, host.getInt("selected")); assertEquals(1, host.getInt("deferred"))
        assertFalse(host.getBoolean("capability_verified")); assertFalse(host.getBoolean("grants_resources"))
        val reopened = CollaborationResearchWorkspace(f.rows).read(f.access(), agenda.getString("object_id"), 1)!!
        assertEquals(3, reopened.getJSONObject("body").getJSONObject("learning_agenda").getJSONArray("options").length())
        assertEquals(2, f.workspace.browseEvolution(f.access()).revisions.size)
    }

    @Test fun invalidRanksEstimatesAndGapOptionsAreRejectedPrecisely() {
        val changes = listOf<(JSONObject) -> Unit>(
            { it.put("priority", 0) }, { it.put("priority", 1) }, { it.put("gap_option", "invented") },
            { it.put("decision", "learned") }, { it.put("information_gain", "") },
            { it.getJSONArray("resource_estimates").getJSONObject(0).put("value", -1) },
            { it.getJSONArray("resource_estimates").getJSONObject(1).put("value", 0) },
            { it.getJSONArray("resource_estimates").getJSONObject(0).put("status", "measured") })
        changes.forEach { change ->
            val result = Fixture().agenda { change(it.getJSONArray("options").getJSONObject(0)) }
            assertEquals(result.toString(), "rejected", result.optString("status"))
        }
    }

    @Test fun allDeferredPublishesWithoutCreatingWorkOrClaimingGoalCompletion() {
        val f = Fixture(); val ref = f.agenda { spec -> val options = spec.getJSONArray("options")
            repeat(options.length()) { options.getJSONObject(it).put("decision", "defer") } }
        assertEquals(0, ref.getJSONObject("host_evolution").getInt("selected"))
        assertTrue(f.plan(ref, emptyList()).work.isEmpty())
        rejected("Deferred") { f.plan(ref, listOf(f.work(ref, "small"))) }
    }

    @Test fun selectionCannotChangeIdentityScopeAssignmentOrExecuteDeferredWork() {
        val f = Fixture(); val ref = f.agenda()
        val bad = listOf<(JSONObject) -> Unit>({ it.put("member", "outsider") }, { it.put("assignment", "Perform an unrelated action") },
            { it.put("stage", "EXECUTE") }, { it.getJSONObject("learning").put("option_id", "unknown") },
            { it.getJSONObject("learning").getJSONObject("agenda").put("sha256", "0".repeat(64)) },
            { it.put("host_learning", JSONObject()) })
        bad.forEach { change -> rejected { f.plan(ref, listOf(f.work(JSONObject(ref.toString()), "small").apply(change))) } }
        rejected("Deferred") { f.plan(ref, listOf(f.work(ref, "later"))) }
        rejected("isolated") { CollaborationLearningWork.plan(f.record(), listOf(f.work(ref, "small")), { f.workspace }, f.access().copy(groupId = "other")) }
        rejected("isolated") { CollaborationLearningWork.plan(f.record(), listOf(f.work(ref, "small")), { f.workspace }, f.access().copy(round = 2, nodeId = "blind-peer")) }
    }

    @Test fun duplicateSelectionAndBindingRemovalFailAfterDurableCodecReopen() {
        val f = Fixture(); val ref = f.agenda(); val plan = f.plan(ref)
        val record = f.record().let { it.copy(request = it.request.copy(context = it.request.context + (CollaborationLearningWork.CLAIMS to plan.claims))) }
        val reopened = reopen(record)
        assertEquals(plan.claims, reopened.request.context[CollaborationLearningWork.CLAIMS])
        assertEquals(plan.claims, f.plan(ref, record = reopened).claims)
        rejected("already assigned") { f.plan(ref, listOf(f.work(ref, "small").put("id", "renamed")), reopened) }
        rejected("remove") { f.plan(ref, listOf(f.work(ref, "small").apply { remove("learning") }), reopened) }
        rejected("already assigned") { f.plan(ref, listOf(f.work(ref, "small"), f.work(ref, "small").put("id", "duplicate"))) }
    }

    @Test fun unavailableWorkspaceDoesNotPartiallyDispatchOrLoseOriginalPlan() {
        val f = Fixture(); val ref = f.agenda(); val item = f.work(ref, "small"); val before = item.toString()
        rejected("unavailable") { CollaborationLearningWork.plan(f.record(), listOf(item), null, f.access()) }
        assertEquals(before, item.toString())
    }

    @Test fun changedGapRejectsOldSelectionAndMarksItsDirectoryHistorical() {
        val f = Fixture(); val ref = f.agenda()
        val gap = f.workspace.read(f.access(), f.gap.getString("object_id"), 1)!!
        val body = gap.getJSONObject("body").apply { getJSONObject("capability_gap").put("symptom", "New contradictory evidence") }
        val update = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Changed gap")
            .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                .put("object_id", f.gap.getString("object_id")).put("base_revision", 1).put("kind", "capability_gap")
                .put("title", "Updated gap").put("body", body)))
        assertEquals("recorded", f.workspace.publish(f.access(), update.toString(), 40).getString("status"))
        rejected("gap changed") { CollaborationLearningWork.plan(f.record(), listOf(f.work(ref, "small")), { f.workspace }, f.access(4)) }
        val listed = f.workspace.browseEvolution(f.access(4)).revisions.single { it.getString("object_id") == ref.getString("object_id") }
        assertEquals("historical_requires_revalidation", listed.getString("evolution_applicability"))
    }

    @Test fun ordinaryWorkNeverLoadsTheLearningWorkspace() {
        val f = Fixture(); val ordinary = JSONObject().put("id", "ordinary").put("assignment", "Normal work")
        val plan = CollaborationLearningWork.plan(f.record(), listOf(ordinary), { error("Unexpected scan") }, f.access())
        assertSame(ordinary, plan.work.single()); assertEquals("{}", plan.claims)
    }

    @Test fun nextRoundAdmissionsAreValidatedAtomicallyAndFollowSavedPriorityInGraph() {
        val f = Fixture(); val ref = f.agenda(); val request = f.report(listOf(f.work(ref, "broad"), f.work(ref, "small")))
        val record = f.finished(f.record(), "lead", request.toString(), true)
        val next = CollaborationGoalLoop.advance(record, "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        val learning = next.definition.members.filter { CollaborationLearningWork.TASK in it.context }
        assertEquals(2, learning.size)
        val graph = AgentTeamGraphPlan.build(next.definition, next.request)
        assertEquals(listOf("learn-small", "learn-broad"), graph.children.filter { c -> learning.any { it.memberId == c.childId } }
            .map { child -> learning.single { it.memberId == child.childId }.context[CollaborationGoalLoop.WORK_ID] })
        val wrong = f.finished(f.record(), "lead", f.report(listOf(f.work(ref, "small"), f.work(ref, "later"))).toString(), true)
        val rejected = CollaborationGoalLoop.advance(wrong, "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        assertTrue(rejected.definition.members.none { it.deliveryMode == AgentDeliveryMode.OBSERVE })
        assertTrue(rejected.request.context[CollaborationWorkGraph.FEEDBACK].toString().contains("Deferred"))
        assertEquals("{}", rejected.request.context[CollaborationLearningWork.CLAIMS])
    }

    @Test fun liveAdmissionsAndRecoveryKeepRunningWorkAndDoNotDuplicateSelection() {
        val f = Fixture(); val ref = f.agenda()
        val base = f.record()
        val people = base.definition.members.map { it.copy(deliveryMode = AgentDeliveryMode.IGNORE) }
        val slow = people.last().copy(instanceId = "slow", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.last().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "slow-work", CollaborationResearchWorkflow.STAGE to "EXECUTE"))
        val planner = people.first().copy(instanceId = "lead-node-3", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.first().context + mapOf(CollaborationLiveGraph.PLANNER to "1", CollaborationGoalLoop.ROSTER to "false"))
        val final = people.first().copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"), dependsOnAgentIds = setOf("slow", planner.memberId))
        val live = base.copy(definition = base.definition.copy(members = people + slow + planner + final, primaryInstanceId = "final"),
            request = base.request.copy(context = base.request.context + (CollaborationGoalLoop.ROUND to "3")))
        val returned = f.finished(live, planner.memberId, JSONObject().put("format", CollaborationLiveGraph.FORMAT)
            .put("summary", "Learn while unrelated work continues").put("work", JSONArray().put(f.work(ref, "small"))).toString())
        val next = CollaborationLiveGraph.update(returned, setOf(planner.memberId), 1000, { f.workspace })
        assertEquals(1, next.definition.members.count { CollaborationLearningWork.TASK in it.context })
        assertEquals(slow, next.definition.members.single { it.memberId == "slow" })
        val restored = reopen(next)
        assertEquals(next.definition, CollaborationLiveGraph.update(restored, setOf(planner.memberId), 2000, { f.workspace }).definition)
    }

    @Test fun failedLearningReceiptsPersistMeasuredDurationButDoNotInventCostOrGain() {
        val f = Fixture(); val selected = f.plan().work.first()
        val member = f.record().definition.members.last().copy(instanceId = "learning-node", context =
            CollaborationLearningWork.context(selected) + (CollaborationGoalLoop.WORK_ID to "learn-broad"))
        val record = f.record().copy(definition = f.record().definition.copy(members = listOf(member)))
        val result = AgentSubagentChildResult("run", member.memberId, "run", 1, AgentSubagentStatus.FAILED,
            "original failed result", startedAtMillis = 10, completedAtMillis = 310)
        val raw = CollaborationLearningFeedback.capture(record, listOf(result))
        val saved = JSONObject(raw).getJSONObject(member.memberId)
        assertEquals(300L, saved.getLong("elapsed_ms")); assertEquals(200.0, saved.getDouble("elapsed_estimate_error_ms"), 0.01)
        assertEquals("failed", saved.getString("status")); assertFalse(saved.getBoolean("capability_verified"))
        assertTrue(saved.isNull("cost_micros")); assertTrue(saved.isNull("learning_gain"))
        val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationLearningFeedback.OUTCOMES to raw)))
        assertEquals(raw, CollaborationLearningFeedback.capture(restored, listOf(result)))
        assertTrue(JSONObject(CollaborationLearningFeedback.capture(record, listOf(result.copy(startedAtMillis = 0))))
            .getJSONObject(member.memberId).isNull("elapsed_ms"))
    }

    @Test fun orderingLeavesOrdinaryWorkInPlaceAndDoesNotEraseDependencies() {
        val f = Fixture(); val items = f.plan().work
        val ordinary = AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "ordinary")
        val learning = items.map { item -> ordinary.copy(instanceId = item.getString("id"),
            dependsOnAgentIds = setOf("producer"), context = CollaborationLearningWork.context(item)) }
        val ordered = CollaborationLearningWork.ordered(listOf(learning[0], ordinary, learning[1]))
        assertEquals(listOf("learn-small", "ordinary", "learn-broad"), ordered.map { it.memberId })
        assertEquals(setOf("producer"), ordered.first().dependsOnAgentIds)
        assertSame(ordinary, ordered[1])
        val resources = JSONObject(CollaborationLearningFeedback.resources(f.record().definition, emptySet(), 1))
        assertEquals(1, resources.getInt("configured_max_concurrency")); assertTrue(resources.isNull("remaining_money"))
    }

    @Test fun runtimeNormalizationHonorsHostOrderingOnlyWhenExplicitlyEnabled() = kotlinx.coroutines.runBlocking {
        for (preserve in listOf(false, true)) {
            val queued = mutableListOf<String>()
            val executed = mutableListOf<String>()
            AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1), kotlinx.coroutines.Dispatchers.Unconfined,
                AgentSubagentEventHook { if (it.kind == AgentSubagentEventKinds.CHILD_QUEUED) queued += it.childId }).use { runtime ->
                runtime.start(AgentSubagentPlan("order-$preserve", listOf("z-first", "a-second", "m-third").map { AgentSubagentChild(it) },
                    preserveChildOrder = preserve)) { execution -> executed += execution.childId; AgentSubagentOutput("fixture") }.await()
            }
            val expected = if (preserve) listOf("z-first", "a-second", "m-third") else listOf("a-second", "m-third", "z-first")
            assertEquals(expected, queued)
            assertEquals(expected, executed)
        }
    }

    private fun rejected(contains: String = "", block: () -> Unit) {
        val failure = runCatching(block).exceptionOrNull()
        assertNotNull("Expected rejection", failure)
        assertTrue(failure.toString(), failure!!.message.orEmpty().contains(contains, true))
    }

    private fun reopen(record: AgentTeamExecutionRecord): AgentTeamExecutionRecord {
        val type = Class.forName("com.galaxyssi.chat.AgentTeamExecutionCodec")
        val instance = type.getDeclaredField("INSTANCE").apply { isAccessible = true }.get(null)
        val encoded = requireNotNull(type.getDeclaredMethod("encode", List::class.java).apply { isAccessible = true }.invoke(instance, listOf(record)))
        @Suppress("UNCHECKED_CAST")
        val decoded = type.getDeclaredMethod("decode", String::class.java).apply { isAccessible = true }
            .invoke(instance, encoded.toString()) as List<AgentTeamExecutionRecord>
        return decoded.single()
    }
}
