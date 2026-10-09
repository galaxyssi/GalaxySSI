package com.galaxyssi.chat

import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationMilestoneDispatchTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        var archiveIndexReads = 0
        override fun read(key: String): String? {
            if (":milestone-record-run:" in key) archiveIndexReads++
            return data[key]
        }
        override fun page(prefix: String, after: String, limit: Int): List<String> {
            if (":milestone-record-run:" in prefix) archiveIndexReads++
            return data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        }
        override fun commit(values: Map<String, String>) { check(!fail); data.putAll(values) }
    }
    private val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "producer", "author")
    private fun raw(id: String = "candidate", ref: JSONObject? = null, observations: JSONArray = JSONArray()): String {
        val item = JSONObject().put("id", id).put("kind", "proposal").put("title", "Candidate $id")
            .put("body", JSONObject().put("content", "Testable method $id")).put("observations", observations)
        ref?.let { item.put("object_id", it.getString("object_id")).put("base_revision", it.getInt("revision")) }
        return JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Interim candidate")
            .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(item)).toString()
    }
    private fun workspace(rows: Rows = Rows()) = CollaborationResearchWorkspace(rows).also {
        it.enrollPublication(author, CollaborationResearchStage.EXECUTE)
    }
    private fun fixture(): AgentTeamExecutionRecord {
        val people = listOf("lead", "author", "peer").map { person -> AgentTeamMember("provider", AgentDeliveryMode.IGNORE,
            instanceId = person, context = mapOf(CollaborationResearchWorkflow.PERSON to person,
                "collaboration_group_id" to "group", CollaborationGoalLoop.ROSTER to "true",
                CollaborationLiveGraph.ENABLED to "1", CollaborationResearchWorkflow.STAGE to "DELIVER")) }
        val producer = people[1].copy(instanceId = "producer", deliveryMode = AgentDeliveryMode.OBSERVE,
            objective = "Develop candidate", context = people[1].context + mapOf(CollaborationGoalLoop.ROSTER to "false",
                CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationGoalLoop.WORK_ID to "original"))
        val dependent = people[2].copy(instanceId = "dependent", deliveryMode = AgentDeliveryMode.OBSERVE,
            objective = "Wait for the whole original assignment", dependsOnAgentIds = setOf("producer"),
            context = people[2].context + mapOf(CollaborationGoalLoop.ROSTER to "false",
                CollaborationResearchWorkflow.STAGE to "VERIFY", CollaborationGoalLoop.WORK_ID to "whole-review"))
        val final = people[0].copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            dependsOnAgentIds = setOf("producer", "dependent"), context = people[0].context + (CollaborationGoalLoop.ROSTER to "false"))
        return AgentTeamExecutionRecord(AgentTeamDefinition("team", "provider", people + producer + dependent + final, primaryInstanceId = "final"),
            AgentRunRequest("group", "turn", "task", runId = "run", goal = "Compare a candidate with evidence",
                createdAtMillis = 1, context = mapOf(CollaborationGoalLoop.ROUND to "1")))
    }
    private fun planned(workspace: CollaborationResearchWorkspace, record: AgentTeamExecutionRecord = fixture()) =
        CollaborationLiveGraph.update(record, emptySet(), 100, { workspace }, milestoneWorkspace = { workspace })
    private fun planner(record: AgentTeamExecutionRecord) = record.definition.members.single(CollaborationLiveGraph::planner)
    private fun item(token: String, person: String = "peer") = JSONObject().put("id", "early-check").put("member", person)
        .put("stage", "VERIFY").put("assignment", "Check the exact candidate against an independent probe")
        .put("uses_milestones", JSONArray().put(token)).put("independent_review", true).put("depends_on", JSONArray())
    private fun expansion(vararg work: JSONObject) = JSONObject().put("format", CollaborationLiveGraph.FORMAT)
        .put("summary", "Review while author continues").put("work", JSONArray(work.toList())).toString()
    private fun returned(record: AgentTeamExecutionRecord, output: String): AgentTeamExecutionRecord {
        val node = planner(record)
        val result = AgentSubagentChildResult("run", node.memberId, "run", 1, AgentSubagentStatus.SUCCEEDED,
            output = output, startedAtMillis = 1, completedAtMillis = 10)
        return record.copy(events = record.events + AgentSubagentEvent(1, "run", node.memberId,
            AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = result.status, result = result, timestampMillis = 10))
    }

    private fun coordination(mode: String) = JSONObject().put("mode", mode).apply { if (mode == "request") {
        put("decision", "Which measurement distinguishes competing candidates?")
        put("why_now", "Independent design can expose the untested confound while I continue calibration")
    } }

    private fun request(vararg ids: String) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Review measurement design").put("coordination", coordination("request"))
        .put("milestones", JSONArray(ids.toList())).toString()

    @Test fun recordOnlyPersistsWithoutSignalOrPlannerAndCanBeEscalatedWithoutCopying() {
        val rows = Rows(); val workspace = workspace(rows); val signals = mutableListOf<String>()
        val saved = JSONObject(raw()).put("coordination", coordination("record_only")).toString()
        val first = CollaborationMilestoneSignals.subscribe(signals::add).use {
            workspace.publishMilestone(author, "raw", saved).also {
                assertEquals(it.toString(), workspace.publishMilestone(author, "raw", saved).toString())
                assertTrue(signals.isEmpty())
            }
        }
        val reopened = CollaborationResearchWorkspace(rows)
        assertEquals(fixture(), planned(reopened))
        assertEquals(1, reopened.pendingMilestones(author, emptySet(), setOf("producer")).size)
        assertEquals("record_only", reopened.milestones(author).getJSONArray("milestones").getJSONObject(0)
            .getJSONObject("coordination").getString("mode"))
        val receipt = CollaborationMilestoneSignals.subscribe(signals::add).use {
            reopened.publishMilestone(author, "help", request("raw"))
        }
        assertEquals(listOf("run"), signals)
        assertEquals(first.getJSONArray("revisions").toString(), receipt.getJSONArray("revisions").toString())
        assertEquals(1, reopened.browse(author).revisions.size)
        val record = planned(reopened)
        val node = planner(record)
        assertEquals("help", CollaborationMilestoneDispatch.inputs(node).single().getString("milestone_id"))
        assertEquals(coordination("request").toString(), CollaborationMilestoneDispatch.inputs(node).single().getJSONObject("coordination").toString())
        val ref = first.getJSONArray("revisions").getJSONObject(0)
        assertNotNull(reopened.read(CollaborationMilestoneDispatch.access(record, node), ref.getString("object_id"), 1))
        assertEquals(record, planned(reopened, record))
        assertEquals("recorded", reopened.submitPublication(author, JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", "Final result").put("milestones", JSONArray(listOf("raw", "help"))).toString()).getString("status"))
        assertEquals(1, reopened.publicationRevisions(author, author.nodeId).size)
    }

    @Test fun archiveOnlyRecordsDoNotConsumeRequestPageAndCoordinatorUpdatesIgnoreThem() {
        val rows = Rows(); val workspace = workspace(rows)
        repeat(35) { workspace.publishMilestone(author, "log-$it", JSONObject(raw("log-$it"))
            .put("coordination", coordination("record_only")).toString()) }
        assertEquals(35, rows.data.keys.count { ":milestone-record-run:" in it })
        assertEquals(fixture(), planned(workspace))
        assertEquals(0, rows.archiveIndexReads)
        workspace.publishMilestone(author, "help", request("log-0", "log-34"))
        val record = planned(workspace); val access = CollaborationMilestoneDispatch.access(record, planner(record))
        val only = workspace.pendingMilestones(access, emptySet(), setOf("producer"), coordinationOnly = true).single()
        assertEquals(2, only.getJSONArray("revisions").length())
        val updates = workspace.coordinatorUpdates(access, "", setOf(only.getString("token")), setOf("producer"))
        assertEquals(0, updates.getJSONArray("milestones").length())
        assertTrue(updates.getBoolean("caught_up_at_read"))
        assertEquals(0, rows.archiveIndexReads)
        assertEquals(16, workspace.pendingMilestones(author, emptySet(), setOf("producer")).size)
    }

    @Test fun coordinationIndexTamperingCannotHideOrInventRequests() {
        for ((mode, replacement) in listOf("request" to "record_only", "record_only" to "request")) {
            val rows = Rows(); val workspace = workspace(rows)
            workspace.publishMilestone(author, "m1", JSONObject(raw()).put("coordination", coordination(mode)).toString())
            val key = rows.data.keys.single { ":milestone-run:" in it || ":milestone-record-run:" in it }
            rows.data[key] = JSONObject(rows.data.getValue(key)).put("coordination", coordination(replacement)).toString()
            assertThrows(IllegalArgumentException::class.java) {
                workspace.pendingMilestones(author, emptySet(), setOf("producer"))
            }
        }
    }

    @Test fun invalidCoordinationAndForeignReferencesDoNotPublishOrWake() {
        val workspace = workspace(); val signals = mutableListOf<String>()
        CollaborationMilestoneSignals.subscribe(signals::add).use {
            for (bad in listOf(JSONObject.NULL, "request", JSONObject().put("mode", "other"),
                JSONObject().put("mode", "request"), coordination("request").put("decision", " "),
                coordination("record_only").put("why_now", "unexpected"))) {
                val result = workspace.publishMilestone(author, "invalid", JSONObject(raw()).put("coordination", bad).toString())
                assertEquals("rejected", result.getString("status"))
            }
            assertEquals("rejected", workspace.publishMilestone(author, "foreign", request("another-assignment")).getString("status"))
            assertTrue(signals.isEmpty())
            assertTrue(workspace.browse(author).revisions.isEmpty())
        }
    }

    @Test fun coordinatorReadsPinnedVersionAndObservationButNotLaterOrUnpublishedResults() {
        val rows = Rows(); val evidenceRows = Rows(); val ledger = CollaborationEvidenceLedger(evidenceRows)
        val workspace = CollaborationResearchWorkspace(rows, evidence = ledger::references).also { it.enrollPublication(author, CollaborationResearchStage.EXECUTE) }
        val evidence = ledger.record(author, "probe", "measure", "{}", "{\"value\":1}", 1, 2)
        val other = ledger.record(author, "private", "measure", "{}", "{\"value\":2}", 2, 3)
        val ref = workspace.publishMilestone(author, "v1", raw(observations = JSONArray().put(evidence))).getJSONArray("revisions").getJSONObject(0)
        val planned = planned(workspace)
        val node = planner(planned)
        assertTrue(node.dependsOnAgentIds.isEmpty())
        val access = CollaborationMilestoneDispatch.access(planned, node)
        assertNotNull(workspace.read(access, ref.getString("object_id"), 1))
        assertNotNull(ledger.read(access, evidence.getString("evidence_id")))
        assertNull(ledger.read(access, other.getString("evidence_id")))
        workspace.publishMilestone(author, "v2", raw(ref = ref))
        assertNull(workspace.read(access, ref.getString("object_id"), 2))
        assertEquals(1, workspace.browse(access).revisions.single().getInt("revision"))
        ledger.bind(12, access)
        assertEquals(access, CollaborationEvidenceLedger(evidenceRows).binding(12, "group", "turn"))
        assertTrue(ledger.authorizes(access)); assertFalse(ledger.authorizes(access.copy(pinnedReads = emptySet())))
        assertNull(workspace.read(access.copy(runId = "foreign"), ref.getString("object_id"), 1))
    }

    @Test fun plannerAddsMilestoneDependentPeerWithoutCompletingAuthorAndSurvivesCodec() {
        val workspace = workspace(); workspace.publishMilestone(author, "v1", raw())
        val first = planned(workspace); val planner = planner(first)
        val token = CollaborationMilestoneDispatch.inputs(planner).single().getString("token")
        val returned = returned(first, expansion(item(token)))
        assertEquals(returned, CollaborationLiveGraph.update(returned, setOf(planner.memberId), 105, { workspace },
            AgentTeamUserControl.PAUSE, milestoneWorkspace = { workspace }))
        val updated = CollaborationLiveGraph.update(returned, setOf(planner.memberId), 110, { workspace }, milestoneWorkspace = { workspace })
        assertEquals("", updated.request.context[CollaborationLiveGraph.FEEDBACK])
        val peer = updated.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == "early-check" }
        assertTrue(peer.dependsOnAgentIds.isEmpty())
        assertEquals(CollaborationMilestoneDispatch.inputs(planner).map(JSONObject::toString), CollaborationMilestoneDispatch.inputs(peer).map(JSONObject::toString))
        assertEquals("true", peer.context[CollaborationWorkGraph.INDEPENDENT])
        assertEquals(first.definition.members.single { it.memberId == "producer" }, updated.definition.members.single { it.memberId == "producer" })
        assertTrue(updated.definition.members.single { it.memberId == "final" }.dependsOnAgentIds.contains(peer.memberId))
        val reopened = reopen(updated)
        assertEquals(updated, reopened)
        assertEquals(updated, CollaborationLiveGraph.update(reopened, setOf(planner.memberId), 120, { workspace }, milestoneWorkspace = { workspace }))
    }

    @Test fun unknownMilestoneAndSelfReviewRejectWholeExpansion() {
        val workspace = workspace(); workspace.publishMilestone(author, "v1", raw())
        val first = planned(workspace); val node = planner(first)
        val token = CollaborationMilestoneDispatch.inputs(node).single().getString("token")
        for (bad in listOf(item("f".repeat(64)), item(token, "author"))) {
            val returned = returned(first, expansion(bad))
            val result = CollaborationLiveGraph.update(returned, setOf(node.memberId), 110, { workspace }, milestoneWorkspace = { workspace })
            assertEquals(returned.definition, result.definition)
            assertTrue(result.request.context[CollaborationLiveGraph.FEEDBACK].toString().isNotBlank())
        }
    }

    @Test fun newVersionsCoalesceBehindActivePlannerAndCreateOnlyOneFollowingCheckpoint() {
        val workspace = workspace(); val v1 = workspace.publishMilestone(author, "v1", raw()).getJSONArray("revisions").getJSONObject(0)
        val first = planned(workspace); val old = planner(first)
        workspace.publishMilestone(author, "v2", raw(ref = v1))
        workspace.publishMilestone(author, "other", raw("other"))
        assertEquals(first, planned(workspace, first))
        val returned = returned(first, expansion())
        val next = CollaborationLiveGraph.update(returned, setOf(old.memberId), 110, { workspace }, milestoneWorkspace = { workspace })
        val added = next.definition.members.single { CollaborationLiveGraph.planner(it) && it.memberId != old.memberId }
        assertEquals(setOf("v2", "other"), CollaborationMilestoneDispatch.inputs(added).map { it.getString("milestone_id") }.toSet())
        assertEquals(next, CollaborationLiveGraph.update(reopen(next), setOf(old.memberId), 120, { workspace }, milestoneWorkspace = { workspace }))
    }

    @Test fun admissionPagesDoNotLosePublicationsAndScopeCannotCrossRunTurnOrRound() {
        val rows = Rows(); val workspace = workspace(rows)
        repeat(35) { workspace.publishMilestone(author, "m$it", raw("candidate$it")) }
        val access = author.copy(nodeId = "coordinator", personId = "lead")
        val seen = hashSetOf<String>()
        repeat(3) {
            val page = CollaborationResearchWorkspace(rows).pendingMilestones(access, seen, setOf("producer"))
            assertEquals(if (it < 2) 16 else 3, page.size)
            page.forEach { value -> assertTrue(seen.add(value.getString("token"))) }
        }
        assertTrue(workspace.pendingMilestones(access, seen, setOf("producer")).isEmpty())
        for (other in listOf(access.copy(runId = "other"), access.copy(turnId = "other"), access.copy(round = 2)))
            assertTrue(workspace.pendingMilestones(other, emptySet(), setOf("producer")).isEmpty())
        assertTrue(workspace.pendingMilestones(access, emptySet(), setOf("unrelated")).isEmpty())
    }

    @Test fun failedCommitDoesNotWakeAndSuccessfulRetryReconcilesFromDisk() {
        val rows = Rows(); val workspace = workspace(rows); val events = mutableListOf<String>()
        CollaborationMilestoneSignals.subscribe(events::add).use {
            rows.fail = true
            assertThrows(IllegalStateException::class.java) { workspace.publishMilestone(author, "m1", raw()) }
            assertTrue(events.isEmpty())
            rows.fail = false
            workspace.publishMilestone(author, "m1", raw())
            assertEquals(listOf("run"), events)
        }
        val recovered = planned(CollaborationResearchWorkspace(rows))
        assertEquals(1, recovered.definition.members.count(CollaborationLiveGraph::planner))
        assertEquals(recovered, planned(CollaborationResearchWorkspace(rows), recovered))
        for (control in AgentTeamUserControl.entries.filter { it != AgentTeamUserControl.RUN })
            assertEquals(fixture(), CollaborationLiveGraph.update(fixture(), emptySet(), 100, { workspace }, control, milestoneWorkspace = { workspace }))
    }

    @Test fun corruptIndexCannotGrantAccessOrWakeAPlanner() {
        val rows = Rows(); val workspace = workspace(rows); workspace.publishMilestone(author, "m1", raw())
        val key = rows.data.keys.single { ":milestone-run:" in it }
        val modified = JSONObject(rows.data.getValue(key))
        modified.getJSONArray("revisions").getJSONObject(0).put("sha256", "a".repeat(64))
        rows.data[key] = modified.toString()
        assertThrows(IllegalArgumentException::class.java) { planned(workspace) }
    }

    @Test fun committedMilestoneWakesLiveRuntimeBeforeProducerEndsAndWholeDependencyStillWaits() = runBlocking {
        withTimeout(10_000) {
            val workspace = workspace(); val fixture = fixture()
            val store = InMemoryAgentTeamExecutionStore().also { it.candidateWorkspace = { workspace }; it.milestoneWorkspace = { workspace } }
            val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
            val peerStarted = CompletableDeferred<AgentTeamMemberExecutionContext>(); val releasePeer = CompletableDeferred<Unit>()
            val dependent = CompletableDeferred<Unit>(); val final = CompletableDeferred<Unit>()
            val calls = CopyOnWriteArrayList<String>()
            AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 3)).use { runtime ->
                val handle = runtime.start(fixture.definition, fixture.request) { execution ->
                    calls += execution.member.memberId
                    when {
                        execution.member.memberId == "producer" -> { started.complete(Unit); release.await(); AgentSubagentOutput("producer finished") }
                        execution.member.memberId == "dependent" -> { dependent.complete(Unit); AgentSubagentOutput("whole assignment checked") }
                        execution.member.memberId == "final" -> { final.complete(Unit); AgentSubagentOutput("Final assessment") }
                        CollaborationLiveGraph.planner(execution.member) -> {
                            val inputs = CollaborationMilestoneDispatch.inputs(execution.member)
                            AgentSubagentOutput(if (inputs.isEmpty()) expansion() else expansion(item(inputs.single().getString("token"))))
                        }
                        execution.member.context[CollaborationGoalLoop.WORK_ID] == "early-check" -> {
                            assertFalse(release.isCompleted)
                            assertTrue(store.records().single().definition.members.contains(execution.member))
                            peerStarted.complete(execution); releasePeer.await(); AgentSubagentOutput("Version independently checked")
                        }
                        else -> error("Unexpected task")
                    }
                }
                try {
                    started.await()
                    val recorded = JSONObject(raw()).put("coordination", coordination("record_only")).toString()
                    workspace.publishMilestone(author, "raw", recorded)
                    assertEquals(fixture, planned(workspace, fixture))
                    assertFalse(peerStarted.isCompleted)
                    val published = workspace.publishMilestone(author, "m1", request("raw"))
                    val peer = peerStarted.await()
                    assertFalse(dependent.isCompleted); assertFalse(final.isCompleted)
                    assertEquals(AgentSubagentStatus.RUNNING, store.snapshot("run")!!.members.single { it.memberId == "producer" }.status)
                    repeat(20) { assertEquals(published.toString(), workspace.publishMilestone(author, "m1", request("raw")).toString()) }
                    release.complete(Unit); dependent.await()
                    assertFalse(final.isCompleted)
                    releasePeer.complete(Unit)
                    assertEquals(AgentSubagentRunStatus.SUCCEEDED, handle.await().subagentResult.status)
                    assertEquals(1, calls.count { it == peer.member.memberId })
                    assertEquals(calls.size, calls.distinct().size)
                } finally { release.complete(Unit); releasePeer.complete(Unit); handle.cancel() }
            }
        }
    }

    private fun reopen(record: AgentTeamExecutionRecord): AgentTeamExecutionRecord {
        val type = Class.forName("com.galaxyssi.chat.AgentTeamExecutionCodec")
        val instance = type.getDeclaredField("INSTANCE").apply { isAccessible = true }.get(null)
        val encode = type.getDeclaredMethod("encode", List::class.java).apply { isAccessible = true }
        val decode = type.getDeclaredMethod("decode", String::class.java).apply { isAccessible = true }
        @Suppress("UNCHECKED_CAST")
        return (decode.invoke(instance, requireNotNull(encode.invoke(instance, listOf(record))).toString()) as List<AgentTeamExecutionRecord>).single()
    }

    @Test fun saturatedWorkersAndQueuedWorkDoNotBlockMilestoneCoordinator() = runBlocking {
        withTimeout(10_000) {
            val workspace = workspace(); val original = fixture()
            val producer = original.definition.members.single { it.memberId == "producer" }
            val extras = listOf("second", "queued").map { id -> producer.copy(instanceId = id,
                context = producer.context + (CollaborationGoalLoop.WORK_ID to id)) }
            val definition = original.definition.copy(members = original.definition.members + extras)
            val store = InMemoryAgentTeamExecutionStore().also { it.milestoneWorkspace = { workspace } }
            val starts = (listOf("producer", "second", "queued")).associateWith { CompletableDeferred<Unit>() }
            val release = CompletableDeferred<Unit>(); val planned = CompletableDeferred<AgentTeamMemberExecutionContext>()
            AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                val handle = runtime.start(definition, original.request) { execution ->
                    when {
                        execution.member.memberId in starts -> {
                            starts.getValue(execution.member.memberId).complete(Unit)
                            release.await(); AgentSubagentOutput("Work completed")
                        }
                        CollaborationLiveGraph.planner(execution.member) -> {
                            if (CollaborationMilestoneDispatch.inputs(execution.member).isNotEmpty()) planned.complete(execution)
                            AgentSubagentOutput(expansion())
                        }
                        else -> AgentSubagentOutput("Checked")
                    }
                }
                try {
                    starts.getValue("producer").await(); starts.getValue("second").await()
                    workspace.publishMilestone(author, "m1", raw())
                    val execution = planned.await()
                    assertFalse(release.isCompleted)
                    assertFalse(starts.getValue("queued").isCompleted)
                    val resources = JSONObject(execution.request.context.getValue(CollaborationLearningFeedback.RESOURCES).toString())
                    assertEquals(2, resources.getInt("configured_work_concurrency"))
                    assertEquals(1, resources.getInt("configured_coordination_concurrency"))
                    assertEquals(3, resources.getInt("configured_max_concurrency"))
                    val saved = reopen(store.records().single())
                    val projected = AgentTeamGraphPlan.build(saved.definition, saved.request)
                    assertEquals(AgentSubagentExecutionLane.COORDINATION,
                        projected.children.single { it.childId == execution.member.memberId }.executionLane)
                    assertTrue(projected.children.filter { it.childId in starts }.all { it.executionLane == AgentSubagentExecutionLane.WORK })
                    release.complete(Unit)
                    assertEquals(AgentSubagentRunStatus.SUCCEEDED, handle.await().subagentResult.status)
                } finally { release.complete(Unit); handle.cancel() }
            }
        }
    }
}
