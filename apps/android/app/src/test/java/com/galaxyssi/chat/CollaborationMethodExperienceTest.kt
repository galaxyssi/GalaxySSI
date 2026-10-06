package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationMethodExperienceTest {
    private class Fixture {
        val t = CollaborationWorkflowTest.Fixture()
        val base = t.f.record()
        val record = CollaborationGoalLoop.advance(t.f.completed(base, "lead", t.f.report(t.work()).toString(), true),
            "lead", 1000, false, candidateWorkspace = { t.f.workspace })!!
        val node = record.definition.members.first { CollaborationWorkflowWork.TASK in it.context }
        val future = t.f.access().copy(runId = "new-run", turnId = "new-turn", round = 0)
        fun result(status: AgentSubagentStatus = AgentSubagentStatus.SUCCEEDED, time: Long = 300) =
            AgentSubagentChildResult("run", node.memberId, "run", 1, status, "original result", errorMessage =
                if (status == AgentSubagentStatus.FAILED) "Source changed during parsing" else "",
                startedAtMillis = 100, completedAtMillis = time,
                collaborationDelivery = CollaborationDeliveryReceipt("rejected", "a".repeat(64), "b".repeat(64), "No accepted result"))
        fun save(result: AgentSubagentChildResult = result()) = t.f.workspace.recordMethodExperience(record, result)
        fun page(access: CollaborationWorkspaceAccess = future, cursor: String = "") = t.f.reopen().methodHistory(access, t.method, cursor)
        fun rows(access: CollaborationWorkspaceAccess = future) = page(access).getJSONArray("records")
    }

    @Test fun reopenedNewTaskReadsExactMethodConditionsAndDoesNotInferQuality() {
        val f = Fixture(); f.save()
        val ref = f.rows().getJSONObject(0)
        val saved = f.t.f.reopen().methodHistoryRecord(f.future, ref.getString("record_id"))!!
        assertEquals(f.t.method.getString("sha256"), saved.getJSONObject("method").getString("sha256"))
        assertEquals(f.t.f.baseline.toString(), saved.getJSONObject("binding").getJSONObject("inputs").getJSONObject("dataset").toString())
        assertEquals(f.node.objective, saved.getString("assignment"))
        assertEquals("succeeded", saved.getString("status"))
        assertEquals("rejected", saved.getJSONObject("delivery").getString("status"))
        assertTrue(saved.isNull("quality_effect")); assertTrue(saved.isNull("causal_contribution"))
    }

    @Test fun repeatedCompletionIsIdempotentAndLateRecoveryPreservesFailure() {
        val f = Fixture(); val failed = f.result(AgentSubagentStatus.FAILED)
        repeat(4) { f.save(failed) }
        assertEquals(1, f.rows().length())
        f.save(f.result(time = 400))
        val rows = f.rows(); assertEquals(2, rows.length())
        assertEquals("failed", rows.getJSONObject(0).getString("status"))
        assertEquals("succeeded", rows.getJSONObject(1).getString("status"))
        assertEquals(rows.getJSONObject(0).getString("node_id"), rows.getJSONObject(1).getString("node_id"))
        val first = f.t.f.reopen().methodHistoryRecord(f.future, rows.getJSONObject(0).getString("record_id"))!!
        assertEquals("Source changed during parsing", first.getString("error"))
    }

    @Test fun independentCurrentPeersCannotReadButAssignedDependenciesCan() {
        val f = Fixture(); f.save()
        val round = f.record.request.context[CollaborationGoalLoop.ROUND].toString().toLong()
        val peer = f.t.f.access("other", round, "other-node")
        assertEquals(0, f.rows(peer).length())
        val id = f.rows().getJSONObject(0).getString("record_id")
        assertNull(f.t.f.workspace.methodHistoryRecord(peer, id))
        assertEquals(1, f.rows(peer.copy(dependencyNodes = setOf(f.node.memberId))).length())
        assertEquals(1, f.rows(peer.copy(round = round + 1)).length())
        assertNull(f.t.f.workspace.methodHistoryRecord(f.future.copy(groupId = "other"), id))
    }

    @Test fun revokedAccessCannotReadOrPublishAndGroupRemovalDeletesHistory() {
        val f = Fixture(); f.save(); val id = f.rows().getJSONObject(0).getString("record_id")
        val denied = CollaborationResearchWorkspace(f.t.f.rows, accessAuthorized = { false })
        assertTrue(runCatching { denied.methodHistoryRecord(f.future, id) }.isFailure)
        denied.recordMethodExperience(f.record, f.result(time = 450))
        assertEquals(1, f.rows().length())
        val removable = object : CollaborationWorkspaceRows by f.t.f.rows {
            override fun mutate(values: Map<String, String>, removeKeys: Collection<String>) {
                removeKeys.forEach(f.t.f.rows.data::remove)
                f.t.f.rows.commit(values)
            }
        }
        CollaborationResearchWorkspace(removable).removeGroup("group")
        assertNull(f.t.f.reopen().methodHistoryRecord(f.future, id))
    }

    @Test fun exactVersionAndHashCannotBeSubstituted() {
        val f = Fixture(); f.save()
        for (ref in listOf(JSONObject(f.t.method.toString()).put("revision", 2),
            JSONObject(f.t.method.toString()).put("sha256", "f".repeat(64)), f.t.f.baseline)) {
            assertTrue(runCatching { f.t.f.workspace.methodHistory(f.future, ref) }.isFailure)
        }
        assertTrue(runCatching { f.save(f.result().copy(supervisorId = "other")) }.isFailure)
        assertTrue(runCatching { f.save(f.result().copy(status = AgentSubagentStatus.RUNNING)) }.isFailure)
        val changed = f.record.copy(definition = f.record.definition.copy(members = f.record.definition.members.map {
            if (it.memberId == f.node.memberId) it.copy(objective = "Different assignment") else it
        }))
        assertTrue(runCatching { f.t.f.workspace.recordMethodExperience(changed, f.result()) }.isFailure)
    }

    @Test fun paginationKeepsAllObservationsAndBindsCursorToAssignment() {
        val f = Fixture(); repeat(45) { f.save(f.result(time = 300L + it)) }
        var page = f.page(); val seen = linkedSetOf<String>(); var count = 0
        val cursor = page.getString("next_cursor")
        assertTrue(cursor.length <= 512)
        assertTrue(runCatching { f.page(f.future.copy(personId = "another"), cursor) }.isFailure)
        do {
            val items = page.getJSONArray("records")
            repeat(items.length()) { seen += items.getJSONObject(it).getString("record_id"); count++ }
            if (page.isNull("next_cursor")) break
            page = f.page(cursor = page.getString("next_cursor"))
        } while (true)
        assertEquals(45, count); assertEquals(45, seen.size)
        assertFalse(page.getBoolean("snapshot"))
    }

    @Test fun emptyIsolatedPageStillLetsReaderReachOlderVisibleObservations() {
        val f = Fixture()
        repeat(22) { f.save(f.result(time = 300L + it)) }
        val peer = f.t.f.access("other", 11, "other-node")
        val page = f.page(peer)
        assertEquals(0, page.getJSONArray("records").length())
        assertFalse(page.isNull("next_cursor"))
    }

    @Test fun ordinaryProgressDoesNotOpenWorkspaceAndCompletedMethodEventsAreCaptured() = runBlocking {
        val f = Fixture(); val store = InMemoryAgentTeamExecutionStore()
        store.create(f.record.definition, f.record.request)
        store.candidateWorkspace = { error("Ordinary progress must not access method history") }
        store.append(AgentSubagentEvent(1, "run", f.node.memberId, AgentSubagentEventKinds.CHILD_RUNNING, childStatus = AgentSubagentStatus.RUNNING))
        store.candidateWorkspace = { f.t.f.workspace }
        store.append(AgentSubagentEvent(2, "run", f.node.memberId, AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = AgentSubagentStatus.SUCCEEDED, result = f.result()))
        assertEquals(1, f.rows().length())
    }

    @Test fun retrievalReturnsExecutableHistorySelectorWithoutLoadingAllExperiences() {
        val f = Fixture(); f.save()
        val results = f.t.f.workspace.searchCapabilities(f.future, "parsing").getJSONArray("records")
        val method = (0 until results.length()).map(results::getJSONObject).single { it.getString("object_id") == f.t.method.getString("object_id") }
        val query = method.getJSONObject("usage_recall")
        assertEquals("method_history", query.getString("mode"))
        assertEquals(f.t.method.getString("sha256"), query.getString("sha256"))
        assertFalse(method.has("records"))
    }

    @Test fun unknownElapsedTimeRemainsUnknown() {
        val f = Fixture(); f.save(f.result().copy(startedAtMillis = 0))
        assertTrue(f.rows().getJSONObject(0).isNull("elapsed_ms"))
    }

    @Test fun storageFailureCanReplayWithoutLosingOrDuplicatingCompletion() = runBlocking {
        val f = Fixture(); val store = InMemoryAgentTeamExecutionStore()
        store.candidateWorkspace = { f.t.f.workspace }
        store.create(f.record.definition, f.record.request)
        val event = AgentSubagentEvent(1, "run", f.node.memberId, AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = AgentSubagentStatus.SUCCEEDED, result = f.result())
        f.t.f.rows.fail = true
        assertTrue(runCatching { store.append(event) }.isFailure)
        f.t.f.rows.fail = false
        store.append(event); store.append(event)
        assertEquals(1, f.rows().length())
        assertEquals(1, store.records().single().events.size)
    }

    @Test fun corruptionIsNotReturnedAsAValidExperience() {
        val f = Fixture(); f.save()
        val id = f.rows().getJSONObject(0).getString("record_id")
        val key = f.t.f.rows.data.keys.single { it.endsWith("method-use:record:$id") }
        f.t.f.rows.data[key] = JSONObject(f.t.f.rows.data.getValue(key)).put("quality_effect", 100).toString()
        assertTrue(runCatching { f.t.f.reopen().methodHistoryRecord(f.future, id) }.isFailure)
    }

    @Test fun retainedProcedureUsageIsAlsoAvailableToLaterTasks() {
        val f = CollaborationProcedureTest.Fixture(); val skill = f.skill()
        val plan = CollaborationProcedureWork.plan(f.record(), listOf(f.work(skill)), { f.workspace }, f.access())
        val binding = CollaborationProcedureWork.context(plan.work.single())
        val base = f.record()
        val node = base.definition.members.last().copy(objective = plan.work.single().getString("assignment"),
            context = base.definition.members.last().context + binding +
            mapOf("collaboration_group_id" to "group", CollaborationResearchWorkflow.PERSON to "peer", CollaborationResearchWorkflow.STAGE to "EXECUTE"))
        val record = base.copy(definition = base.definition.copy(members = listOf(base.definition.members.first(), node)),
            request = base.request.copy(context = base.request.context + (CollaborationGoalLoop.ROUND to "20")))
        f.workspace.recordMethodExperience(record, AgentSubagentChildResult(base.request.runId, node.memberId, base.request.runId,
            1, AgentSubagentStatus.FAILED, errorMessage = "A required input became unavailable"))
        val future = f.access().copy(runId = "new-run", turnId = "new-turn", round = 0)
        val history = f.experiment.workspace().methodHistory(future, skill)
        assertEquals("failed", history.getJSONArray("records").getJSONObject(0).getString("status"))
    }
}
