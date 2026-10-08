package com.galaxyssi.chat

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentTeamLiveGraphIntegrationTest {
    @Test fun producerTriggersPersistedReviewWhileSlowWorkRunsAndFinalWaitsForTheReview() = runBlocking {
        withTimeout(10_000) {
            val store = InMemoryAgentTeamExecutionStore()
            val fixture = fixture()
            val slowStarted = CompletableDeferred<Unit>()
            val releaseSlow = CompletableDeferred<Unit>()
            val slowPersisted = CompletableDeferred<Unit>()
            val reviewStarted = CompletableDeferred<AgentTeamMemberExecutionContext>()
            val releaseReview = CompletableDeferred<Unit>()
            val finalStarted = CompletableDeferred<AgentTeamMemberExecutionContext>()
            val plannerCalls = AtomicInteger()
            val finalCalls = AtomicInteger()
            val dispatches = CopyOnWriteArrayList<String>()
            AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 2), onSnapshot = { snapshot ->
                if (snapshot.members.any { it.memberId == SLOW && it.status == AgentSubagentStatus.SUCCEEDED }) {
                    slowPersisted.complete(Unit)
                }
            }).use { runtime ->
                val handle = runtime.start(fixture.definition, fixture.request) { execution ->
                    dispatches += execution.member.memberId
                    assertEquals(fixture.request.goal, execution.request.goal)
                    assertEquals(fixture.request.context[CollaborationGoalLoop.CRITERIA], execution.request.context[CollaborationGoalLoop.CRITERIA])
                    assertEquals(fixture.request.context[CollaborationGoalLoop.ROUND], execution.request.context[CollaborationGoalLoop.ROUND])
                    when {
                        CollaborationLiveGraph.planner(execution.member) -> {
                            assertTrue(store.records().single().definition.members.contains(execution.member))
                            if (plannerCalls.incrementAndGet() == 1) {
                                assertTrue(slowStarted.isCompleted)
                                assertFalse(releaseSlow.isCompleted)
                                assertEquals("producer-output", execution.handoff.dependencies.single().output)
                                val inventory = JSONObject(execution.request.context["collaboration_research_live_inventory"].toString())
                                val items = inventory.getJSONArray("items")
                                val producer = (0 until items.length()).map { items.getJSONObject(it) }
                                    .single { it.getString("id") == PRODUCER_WORK }
                                assertEquals(AgentSubagentStatus.SUCCEEDED.name, producer.getString("status"))
                                val slow = (0 until items.length()).map { items.getJSONObject(it) }
                                    .single { it.getString("id") == "slow-work" }
                                assertEquals("RUNNING", slow.getString("status"))
                                assertEquals("satisfied", slow.getString("dependency_state"))
                                AgentSubagentOutput(expansion(includeReview = true))
                            } else AgentSubagentOutput(expansion())
                        }
                        execution.member.memberId == PRODUCER -> {
                            slowStarted.await()
                            AgentSubagentOutput("producer-output")
                        }
                        execution.member.memberId == SLOW -> {
                            slowStarted.complete(Unit)
                            releaseSlow.await()
                            AgentSubagentOutput("slow-output")
                        }
                        execution.member.context[CollaborationGoalLoop.WORK_ID] == REVIEW_WORK -> {
                            val persisted = store.records().single()
                            assertTrue(persisted.definition.members.contains(execution.member))
                            assertTrue(persisted.definition.members.single { it.memberId == FINAL }.dependsOnAgentIds.contains(execution.member.memberId))
                            assertTrue(persisted.events.any { it.result != null && it.childId in applied(persisted) })
                            assertFalse(releaseSlow.isCompleted)
                            assertEquals(setOf(PRODUCER), execution.member.dependsOnAgentIds)
                            assertEquals("producer-output", execution.handoff.dependencies.single().output)
                            assertEquals(REVIEWER, execution.member.context[CollaborationResearchWorkflow.PERSON])
                            assertEquals(stableAgentTeamMemberRunId(RUN, execution.member.memberId), execution.request.runId)
                            assertEquals("${fixture.request.idempotencyKey}:${execution.member.memberId}", execution.request.idempotencyKey)
                            reviewStarted.complete(execution)
                            releaseReview.await()
                            AgentSubagentOutput("review-output")
                        }
                        execution.member.memberId == FINAL -> {
                            finalCalls.incrementAndGet()
                            finalStarted.complete(execution)
                            assertTrue(releaseReview.isCompleted)
                            assertTrue(releaseSlow.isCompleted)
                            assertTrue(execution.handoff.dependencies.any { it.output == "review-output" })
                            assertTrue(execution.handoff.dependencies.any { it.childId == SLOW && it.output == "slow-output" })
                            AgentSubagentOutput(assessment())
                        }
                        else -> error("Unexpected dispatch ${execution.member.memberId}")
                    }
                }
                try {
                    val review = reviewStarted.await()
                    assertFalse(finalStarted.isCompleted)
                    assertEquals(AgentTeamExecutionState.RUNNING, store.snapshot(RUN)?.state)
                    releaseSlow.complete(Unit)
                    slowPersisted.await()
                    assertFalse("The added review, not only the original slow member, must hold final", finalStarted.isCompleted)
                    releaseReview.complete(Unit)
                    val result = handle.await()
                    assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.subagentResult.status)
                    assertEquals("Reviewed progress", result.finalOutput)
                    assertEquals(FINAL, result.snapshot.primaryMemberId)
                    assertEquals(1, finalCalls.get())
                    assertEquals(1, dispatches.count { it == PRODUCER })
                    assertEquals(1, dispatches.count { it == review.member.memberId })
                    assertEquals(dispatches.size, dispatches.distinct().size)
                    assertTrue(dispatches.indexOf(review.member.memberId) < dispatches.indexOf(FINAL))
                } finally {
                    releaseSlow.complete(Unit)
                    releaseReview.complete(Unit)
                    handle.cancel()
                }
            }
        }
    }

    @Test fun productionCodecReopensTheAppendedCheckpointUsedByRuntimeResume() = runBlocking {
        withTimeout(10_000) {
            val original = seedPersistedExpansion()
            val saved = original.records().single()
            val decoded = Codec.decode(Codec.encode(saved))
            assertEquals(saved, decoded)
            val reopened = reopen(decoded)
            val checkpoint = requireNotNull(reopened.resumeCheckpoint(RUN))
            assertEquals(original.resumeCheckpoint(RUN), checkpoint)
            val review = checkpoint.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == REVIEW_WORK }
            val completed = checkpoint.completed.keys
            assertEquals(setOf(PRODUCER) + saved.definition.members.filter(CollaborationLiveGraph::planner).map { it.memberId }, completed)
            assertTrue(checkpoint.definition.members.single { it.memberId == FINAL }.dependsOnAgentIds.contains(review.memberId))
            val invoked = CopyOnWriteArrayList<String>()
            AgentTeamExecutionRuntime(reopened, AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                val result = runtime.resume(checkpoint) { execution ->
                    invoked += execution.member.memberId
                    assertFalse("Completed checkpoint work must not execute again", execution.member.memberId in completed)
                    resumedOutput(execution)
                }.await()
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.subagentResult.status)
                assertEquals("Reviewed progress", result.finalOutput)
                assertEquals(1, invoked.count { it == review.memberId })
                assertEquals(1, invoked.count { it == FINAL })
                assertEquals(saved.request.goal, result.snapshot.goal)
                assertNoReplayEvents(reopened, checkpoint)
            }
        }
    }

    @Test fun crashAfterDurableAppendRecoversWithoutReplayingCompletedSideEffects() = runBlocking {
        withTimeout(10_000) {
            val durable = InMemoryAgentTeamExecutionStore()
            val crashStore = CrashAfterReviewAppendStore(durable)
            val fixture = fixture()
            val slowStarted = CompletableDeferred<Unit>()
            val producerEffects = AtomicInteger()
            val firstDispatches = CopyOnWriteArrayList<String>()
            AgentTeamExecutionRuntime(crashStore, AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                val handle = runtime.start(fixture.definition, fixture.request) { execution ->
                    firstDispatches += execution.member.memberId
                    when {
                        execution.member.memberId == PRODUCER -> {
                            slowStarted.await()
                            producerEffects.incrementAndGet()
                            AgentSubagentOutput("producer-output")
                        }
                        execution.member.memberId == SLOW -> {
                            slowStarted.complete(Unit)
                            awaitCancellation()
                        }
                        CollaborationLiveGraph.planner(execution.member) -> AgentSubagentOutput(expansion(includeReview = true))
                        else -> error("Dispatch happened after the injected process loss")
                    }
                }
                val failure = runCatching { handle.await() }.exceptionOrNull()
                assertNotNull(failure)
                assertEquals(CRASH_MESSAGE, failure?.message)
            }

            val persisted = Codec.decode(requireNotNull(crashStore.crashImage))
            val review = persisted.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == REVIEW_WORK }
            assertFalse(firstDispatches.contains(review.memberId))
            assertFalse(firstDispatches.contains(FINAL))
            assertFalse(persisted.events.any { it.childId == review.memberId })
            assertTrue(persisted.events.none { it.runStatus != null })
            assertEquals(1, applied(persisted).size)
            val reopened = reopen(persisted)
            reopened.markInterrupted(RUN, persisted.updatedAtMillis + 1)
            assertNull("An outstanding remote dispatch cannot be silently replayed", reopened.resumeCheckpoint(RUN))
            assertTrue(reopened.applyLateResponse(AgentManagedResponseRecord(
                stableAgentTeamMemberRunId(RUN, SLOW), RUN, PROVIDER, AgentDeliveryMode.OBSERVE, 71L, PROVIDER,
                conversationId = GROUP, turnId = TURN, taskId = TASK, state = AgentManagedResponseState.COMPLETED,
                response = AgentConnectorResponse(71L, PROVIDER, "slow-output", GROUP, TURN, TASK),
                createdAtMillis = 1)))
            val checkpoint = requireNotNull(reopened.resumeCheckpoint(RUN))
            assertTrue(checkpoint.completed.keys.containsAll(setOf(PRODUCER, SLOW) + applied(persisted)))
            assertEquals(review, checkpoint.definition.members.single { it.memberId == review.memberId })
            val resumed = CopyOnWriteArrayList<String>()
            AgentTeamExecutionRuntime(reopened, AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                val result = runtime.resume(checkpoint) { execution ->
                    resumed += execution.member.memberId
                    if (execution.member.memberId == PRODUCER) producerEffects.incrementAndGet()
                    assertFalse("A reconciled side effect must not execute again", execution.member.memberId in checkpoint.completed)
                    resumedOutput(execution)
                }.await()
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.subagentResult.status)
                assertEquals(1, producerEffects.get())
                assertEquals(1, resumed.count { it == review.memberId })
                assertEquals(1, resumed.count { it == FINAL })
                assertEquals(resumed.size, resumed.distinct().size)
                assertNoReplayEvents(reopened, checkpoint)
            }
        }
    }

    @Test fun supervisorStartAndTerminalAnchorsSurviveTheEventTailBoundaryAndCodecReopen() = runBlocking {
        val limit = InMemoryAgentTeamExecutionStore.MAX_EVENTS_PER_RUN
        for (count in listOf(limit - 1, limit, limit + 1)) {
            val record = largeFixture(count)
            val store = InMemoryAgentTeamExecutionStore()
            store.create(record.definition, record.request)
            store.append(started(record.request.runId))
            record.definition.members.forEachIndexed { index, member ->
                store.append(succeeded(record.request.runId, member.memberId, index + 2L, "result-$index"))
            }
            assertTrue(store.records().single().events.any { it.kind == AgentSubagentEventKinds.SUPERVISOR_STARTED })
            assertEquals(AgentTeamExecutionState.RUNNING, store.snapshot(record.request.runId)?.state)
            val terminalSequence = count + 2L
            store.append(AgentSubagentEvent(terminalSequence, record.request.runId,
                kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED,
                timestampMillis = terminalSequence))

            val reopened = reopen(Codec.decode(Codec.encode(store.records().single())))
            val saved = reopened.records().single()
            val snapshot = requireNotNull(reopened.snapshot(record.request.runId))
            assertEquals(AgentTeamExecutionState.SUCCEEDED, snapshot.state)
            assertEquals(count, snapshot.members.count { it.status == AgentSubagentStatus.SUCCEEDED })
            assertEquals(terminalSequence, saved.events.last().sequence)
            assertEquals(AgentSubagentRunStatus.SUCCEEDED, saved.events.single { it.runStatus != null }.runStatus)
            assertEquals(count, saved.events.mapNotNull { it.result }.size)
            assertTrue(reopened.markNonTerminalInterrupted(10_000).isEmpty())
            assertNull(reopened.resumeCheckpoint(record.request.runId))
        }
    }

    @Test fun moreThan512CompletedNodesRemainRecoverableWithTheirSupervisorAndSequence() = runBlocking {
        val completedCount = InMemoryAgentTeamExecutionStore.MAX_EVENTS_PER_RUN + 1
        val record = largeFixture(completedCount + 1)
        val store = InMemoryAgentTeamExecutionStore()
        store.create(record.definition, record.request)
        store.append(started(record.request.runId))
        record.definition.members.dropLast(1).forEachIndexed { index, member ->
            store.append(succeeded(record.request.runId, member.memberId, index + 2L, "completed-evidence-$index"))
        }
        val sequence = completedCount + 2L
        store.append(AgentSubagentEvent(sequence, record.request.runId, record.definition.primaryMemberId,
            AgentSubagentEventKinds.CHILD_QUEUED, childStatus = AgentSubagentStatus.QUEUED, timestampMillis = sequence))
        store.markInterrupted(record.request.runId, 10_000)
        val reopened = reopen(Codec.decode(Codec.encode(store.records().single())))
        val checkpoint = requireNotNull(reopened.resumeCheckpoint(record.request.runId))

        assertEquals(completedCount, checkpoint.completed.size)
        assertEquals(sequence, checkpoint.lastSequence)
        assertEquals("completed-evidence-0", checkpoint.completed.getValue("large-node-0").output)
        assertEquals("completed-evidence-${completedCount - 1}", checkpoint.completed.getValue("large-node-${completedCount - 1}").output)
        assertFalse(checkpoint.completed.containsKey(record.definition.primaryMemberId))
        assertEquals(AgentTeamExecutionState.INTERRUPTED, reopened.snapshot(record.request.runId)?.state)
        assertTrue(reopened.records().single().events.any { it.kind == AgentSubagentEventKinds.SUPERVISOR_STARTED })
    }

    @Test fun codecPreservesLongOriginalGoalMemberMetadataAndAcceptanceBindingsExactly() = runBlocking {
        val saved = seedPersistedExpansion().records().single()
        val longGoal = "Original requirement:\n" + "Preserve the complete user goal. ".repeat(800) + "EXACT-END"
        val longCriteria = JSONArray().put(JSONObject().put("id", "criterion-1")
            .put("requirement", "Preserve this acceptance requirement. ".repeat(300))
            .put("status", "open").put("evidence", JSONArray())).toString()
        val longIds = JSONArray((0 until 900).map { "completed-dispatch-identity-$it" }).toString()
        assertTrue(longGoal.length > 16_000)
        assertTrue(longCriteria.length > 8_000)
        assertTrue(longIds.length > 8_000)
        val request = saved.request.copy(goal = longGoal, context = saved.request.context + mapOf(
            CollaborationGoalLoop.CRITERIA to longCriteria, CollaborationGoalLoop.FINISHED_WORK to longIds,
            CollaborationLiveGraph.APPLIED to longIds))
        val definition = saved.definition.copy(members = saved.definition.members.map { member ->
            if (CollaborationLiveGraph.planner(member)) member.copy(context = member.context +
                (CollaborationLiveGraph.SOURCES to longIds)) else member
        })
        val output = assessment()
        val receipt = CollaborationAcceptanceReceipt(AgentNativeJsonCodec.sha256(output), AgentNativeJsonCodec.sha256(longCriteria),
            AgentNativeJsonCodec.sha256(longGoal), RUN, TURN, FINAL, true, "Host fixture receipt", 100)
        val sequence = saved.events.last().sequence + 1
        val finalEvent = succeeded(RUN, FINAL, sequence, output).let { event ->
            event.copy(result = requireNotNull(event.result).copy(collaborationAcceptance = receipt))
        }
        val record = saved.copy(definition = definition, request = request, events = saved.events + finalEvent, updatedAtMillis = 100)
        val decoded = Codec.decode(Codec.encode(record))

        assertEquals(record, decoded)
        assertEquals(longGoal, decoded.request.goal)
        assertEquals(longCriteria, decoded.request.context[CollaborationGoalLoop.CRITERIA])
        assertEquals(longIds, decoded.request.context[CollaborationLiveGraph.APPLIED])
        assertEquals(longIds, decoded.definition.members.single(CollaborationLiveGraph::planner).context[CollaborationLiveGraph.SOURCES])
        assertEquals(900, JSONArray(decoded.request.context[CollaborationGoalLoop.FINISHED_WORK].toString()).length())
        assertTrue(decoded.acceptanceVerified(decoded.events.last().result))
        assertEquals(receipt, decoded.events.last().result?.collaborationAcceptance)
    }

    private fun fixture(): AgentTeamExecutionRecord {
        val people = listOf(LEAD, AUTHOR, REVIEWER, SLOW_PERSON).map { person -> AgentTeamMember(
            PROVIDER, AgentDeliveryMode.IGNORE, instanceId = person, role = "Researcher", context = mapOf(
                CollaborationLiveGraph.ENABLED to "1", CollaborationGoalLoop.ENABLED to "1",
                CollaborationGoalLoop.ROSTER to "true", CollaborationResearchWorkflow.PERSON to person,
                CollaborationResearchWorkflow.STAGE to "DELIVER", "collaboration_group_id" to GROUP,
                "collaboration_name" to person, "collaboration_model_id" to "authorized-model")) }
        fun work(person: String, id: String, workId: String) = people.single { it.memberId == person }.let { template ->
            template.copy(instanceId = id, deliveryMode = AgentDeliveryMode.OBSERVE, objective = "Produce $workId",
                context = template.context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to workId,
                    CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationWorkGraph.POLICY to "success",
                    CollaborationWorkGraph.INDEPENDENT to "false"))
        }
        val nodes = listOf(work(AUTHOR, PRODUCER, PRODUCER_WORK), work(SLOW_PERSON, SLOW, "slow-work"))
        val final = people.first().copy(instanceId = FINAL, deliveryMode = AgentDeliveryMode.RESPOND,
            objective = "Assess the original goal", dependsOnAgentIds = nodes.map { it.memberId }.toSet(),
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"))
        return AgentTeamExecutionRecord(AgentTeamDefinition("integration-team", PROVIDER, people + nodes + final,
            primaryInstanceId = FINAL), AgentRunRequest(GROUP, TURN, TASK, runId = RUN, goal = "Deliver an independently reviewed artifact",
            idempotencyKey = "integration-key", createdAtMillis = 1, context = mapOf(
                CollaborationGoalLoop.ROUND to "4", CollaborationGoalLoop.CRITERIA to criteria().toString(),
                CollaborationGoalLoop.HOST_ACCEPTANCE to "1", "collaboration_research_recovery_version" to "2")))
    }

    private fun criteria() = JSONArray().put(JSONObject().put("id", "criterion-1")
        .put("requirement", "Independently reviewed artifact").put("status", "open").put("evidence", JSONArray()))

    private fun assessment() = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Reviewed progress")
        .put("decision", "continue").put("criteria", criteria()).put("work", JSONArray()).put("blockers", JSONArray()).toString()

    private fun expansion(includeReview: Boolean = false) = JSONObject().put("format", CollaborationLiveGraph.FORMAT)
        .put("summary", "Inspect the produced artifact").put("work", JSONArray().apply {
            if (includeReview) put(JSONObject().put("id", REVIEW_WORK).put("member", REVIEWER).put("stage", "VERIFY")
                .put("assignment", "Independently verify the producer output").put("depends_on", JSONArray().put(PRODUCER_WORK))
                .put("dependency_policy", "success").put("independent_review", true))
        }).toString()

    private fun resumedOutput(execution: AgentTeamMemberExecutionContext): AgentSubagentOutput = when {
        CollaborationLiveGraph.planner(execution.member) -> AgentSubagentOutput(expansion())
        execution.member.memberId == SLOW -> AgentSubagentOutput("slow-output")
        execution.member.context[CollaborationGoalLoop.WORK_ID] == REVIEW_WORK -> {
            assertEquals("producer-output", execution.handoff.dependencies.single().output)
            AgentSubagentOutput("review-output")
        }
        execution.member.memberId == FINAL -> {
            assertTrue(execution.handoff.dependencies.any { it.output == "review-output" })
            AgentSubagentOutput(assessment())
        }
        else -> error("Unexpected recovered dispatch ${execution.member.memberId}")
    }

    private suspend fun seedPersistedExpansion(): InMemoryAgentTeamExecutionStore {
        val record = fixture()
        val store = InMemoryAgentTeamExecutionStore()
        store.create(record.definition, record.request)
        store.append(started(RUN))
        listOf(PRODUCER, SLOW, FINAL).forEachIndexed { index, id ->
            store.append(AgentSubagentEvent(index + 2L, RUN, id, AgentSubagentEventKinds.CHILD_QUEUED,
                childStatus = AgentSubagentStatus.QUEUED, timestampMillis = index + 2L))
        }
        store.append(succeeded(RUN, PRODUCER, 5, "producer-output"))
        val planned = requireNotNull(store.expandResearchGraph(RUN, FINAL, setOf(PRODUCER), 10))
        val planner = planned.definition.members.single(CollaborationLiveGraph::planner)
        store.append(succeeded(RUN, planner.memberId, 6, expansion(includeReview = true)))
        store.expandResearchGraph(RUN, FINAL, setOf(PRODUCER, planner.memberId), 20)
        store.markInterrupted(RUN, 100)
        return store
    }

    private suspend fun reopen(record: AgentTeamExecutionRecord): InMemoryAgentTeamExecutionStore {
        val store = InMemoryAgentTeamExecutionStore()
        store.create(record.definition, record.request)
        record.events.forEach { store.append(it) }
        if (record.interruptedAtMillis > 0) store.markInterrupted(record.request.runId, record.interruptedAtMillis)
        return store
    }

    private fun assertNoReplayEvents(store: InMemoryAgentTeamExecutionStore, checkpoint: AgentTeamExecutionCheckpoint) {
        val events = store.records().single().events
        assertTrue(events.filter { it.sequence > checkpoint.lastSequence && it.kind == AgentSubagentEventKinds.CHILD_RUNNING }
            .none { it.childId in checkpoint.completed })
        assertEquals(events.size, events.map { it.sequence }.distinct().size)
        assertEquals(events.map { it.sequence }.sorted(), events.map { it.sequence })
        assertTrue(events.any { it.sequence > checkpoint.lastSequence && it.kind == AgentSubagentEventKinds.SUPERVISOR_STARTED })
    }

    private fun largeFixture(count: Int): AgentTeamExecutionRecord {
        val nodes = (0 until count).map { index -> AgentTeamMember(PROVIDER,
            if (index == count - 1) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE, instanceId = "large-node-$index") }
        return AgentTeamExecutionRecord(AgentTeamDefinition("large-team", PROVIDER, nodes, primaryInstanceId = nodes.last().memberId),
            AgentRunRequest(GROUP, TURN, TASK, runId = "large-run-$count", goal = "Preserve every completed node", createdAtMillis = 1))
    }

    private fun started(runId: String) = AgentSubagentEvent(1, runId, kind = AgentSubagentEventKinds.SUPERVISOR_STARTED, timestampMillis = 1)

    private fun succeeded(runId: String, childId: String, sequence: Long, output: String) = AgentSubagentEvent(
        sequence, runId, childId, AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = AgentSubagentStatus.SUCCEEDED,
        result = AgentSubagentChildResult(runId, childId, runId, 1, AgentSubagentStatus.SUCCEEDED,
            output = output, startedAtMillis = 1, completedAtMillis = sequence), timestampMillis = sequence)

    private fun applied(record: AgentTeamExecutionRecord) = JSONArray(record.request.context[CollaborationLiveGraph.APPLIED]?.toString() ?: "[]")
        .let { array -> (0 until array.length()).map { array.getString(it) }.toSet() }

    private class CrashAfterReviewAppendStore(private val backing: InMemoryAgentTeamExecutionStore) : AgentTeamExecutionStore by backing {
        @Volatile var crashImage: String? = null
            private set

        override fun expandResearchGraph(supervisorRunId: String, expectedPrimary: String, completedIds: Set<String>,
                                         nowMillis: Long, candidateAdmission: Int): AgentTeamExecutionCheckpoint? {
            val checkpoint = backing.expandResearchGraph(supervisorRunId, expectedPrimary, completedIds, nowMillis, candidateAdmission)
            if (crashImage == null && checkpoint?.definition?.members?.any { it.context[CollaborationGoalLoop.WORK_ID] == REVIEW_WORK } == true) {
                // Capture the durable commit, excluding cleanup events a real process loss could not write.
                crashImage = Codec.encode(backing.records().single())
                throw IllegalStateException(CRASH_MESSAGE)
            }
            return checkpoint
        }
    }

    // Exercise the encrypted store's actual private serialization without Android storage or a device.
    private object Codec {
        private val type = Class.forName("com.galaxyssi.chat.AgentTeamExecutionCodec")
        private val instance = type.getDeclaredField("INSTANCE").apply { isAccessible = true }.get(null)
        private val encode = type.getDeclaredMethod("encode", List::class.java).apply { isAccessible = true }
        private val decode = type.getDeclaredMethod("decode", String::class.java).apply { isAccessible = true }

        fun encode(record: AgentTeamExecutionRecord): String = requireNotNull(encode.invoke(instance, listOf(record))).toString()

        @Suppress("UNCHECKED_CAST")
        fun decode(raw: String): AgentTeamExecutionRecord = (decode.invoke(instance, raw) as List<AgentTeamExecutionRecord>).single()
    }

    private companion object {
        const val GROUP = "integration-group"
        const val TURN = "integration-turn"
        const val TASK = "integration-task"
        const val RUN = "integration-run"
        const val PROVIDER = "shared-provider"
        const val LEAD = "coordinator-person"
        const val AUTHOR = "author-person"
        const val REVIEWER = "reviewer-person"
        const val SLOW_PERSON = "slow-person"
        const val PRODUCER = "producer-dispatch"
        const val SLOW = "slow-dispatch"
        const val FINAL = "final-dispatch"
        const val PRODUCER_WORK = "produce-artifact"
        const val REVIEW_WORK = "review-artifact"
        const val CRASH_MESSAGE = "Injected process loss after durable review append"
    }
}
