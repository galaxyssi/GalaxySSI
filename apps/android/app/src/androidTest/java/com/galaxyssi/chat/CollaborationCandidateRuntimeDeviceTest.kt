package com.galaxyssi.chat

import android.content.Context
import android.os.Bundle
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Encrypted local fixtures only. Does not call providers or touch production team data. */
@RunWith(AndroidJUnit4::class)
class CollaborationCandidateRuntimeDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private class Rows(private val db: AgentEncryptedDatabase) : CollaborationWorkspaceRows {
        override fun read(key: String) = db.readString(key, "").takeIf(String::isNotBlank)
        override fun commit(values: Map<String, String>) = db.mutateStrings(values)
        override fun page(prefix: String, after: String, limit: Int) = db.keysAfter(prefix, after, limit)
    }
    private inner class Fixture(name: String) {
        val teamDb = AgentEncryptedDatabase(context, "$name-team")
        private val workspaceDb = AgentEncryptedDatabase(context, "$name-workspace")
        private val evidenceDb = AgentEncryptedDatabase(context, "$name-evidence")
        val f = CandidateRuntimeFixture(Rows(workspaceDb), Rows(evidenceDb))
        fun store() = EncryptedAgentTeamExecutionStore(teamDb, candidateWorkspace = { f.workspace })
        fun clear() { teamDb.clear(); workspaceDb.clear(); evidenceDb.clear() }
    }

    @Test fun encryptedRuntimeAdvancesTwoCandidateRoutesWhileUnrelatedWorkRemainsActive(): Unit = runBlocking {
        withTimeout(60_000) {
            val fixture = Fixture("candidate-runtime-${UUID.randomUUID()}")
            val f = fixture.f
            val store = fixture.store()
            val record = f.record()
            val slowStarted = CompletableDeferred<Unit>()
            val releaseSlow = CompletableDeferred<Unit>()
            val settled = CompletableDeferred<Unit>()
            val enrolled = AtomicBoolean()
            val operations = CopyOnWriteArrayList<String>()
            try {
                AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 3), onSnapshot = { snapshot ->
                    if (snapshot.members.count { it.status == AgentSubagentStatus.SUCCEEDED &&
                            it.researchStage in setOf("VERIFY", "REVISE") } == 4) settled.complete(Unit)
                }).use { runtime ->
                    val handle = runtime.start(record.definition, record.request) { execution ->
                        val member = execution.member
                        when {
                            member.memberId == "producer" -> { slowStarted.await(); AgentSubagentOutput(f.produce()) }
                            member.memberId == "slow" -> { slowStarted.complete(Unit); releaseSlow.await(); AgentSubagentOutput("slow-result") }
                            CollaborationLiveGraph.planner(member) -> AgentSubagentOutput(f.expansion(!enrolled.getAndSet(true)))
                            member.context.containsKey(CollaborationCandidateEvolution.TASK) -> {
                                assertFalse(releaseSlow.isCompleted)
                                assertTrue(fixture.store().snapshot(record.request.runId)!!.members.any { it.memberId == member.memberId })
                                val task = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
                                operations += task.getString("operation")
                                val refute = task.getString("member") == "reviewer-a" && task.getJSONObject("target").getInt("revision") == 1
                                AgentSubagentOutput(f.execute(member, if (refute) "refuted" else "supported"))
                            }
                            else -> { assertTrue(settled.isCompleted && releaseSlow.isCompleted); AgentSubagentOutput(f.assessment()) }
                        }
                    }
                    try {
                        settled.await()
                        assertEquals(3, operations.count { it == "review" })
                        assertEquals(1, operations.count { it == "revise" })
                        releaseSlow.complete(Unit)
                        assertEquals(AgentSubagentRunStatus.SUCCEEDED, handle.await().subagentResult.status)
                        assertEquals("continue", fixture.store().snapshot(record.request.runId)!!.goalDisposition)
                    } finally { releaseSlow.complete(Unit); handle.cancel() }
                }
            } finally { fixture.clear() }
        }
    }

    @Test fun separateProcessRestoresCandidateGraphAndReplaysSavedPublication(): Unit = runBlocking {
        val phase = InstrumentationRegistry.getArguments().getString("candidatePhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val fixture = Fixture("candidate-runtime-process-fixture")
        val f = fixture.f
        val record = f.record()
        val store = fixture.store()
        val prefs = context.getSharedPreferences("candidate-runtime-process-fixture", Context.MODE_PRIVATE)
        withTimeout(60_000) {
            if (phase == "seed") {
                require(store.snapshot(record.request.runId) == null) { "Recover the previous fixture before seeding" }
                store.create(record.definition, record.request)
                complete(store, "producer", f.produce(), 1)
                val planned = store.expandResearchGraph(record.request.runId, "final", setOf("producer"), 2)!!
                val planner = planned.definition.members.single(CollaborationLiveGraph::planner)
                complete(store, planner.memberId, f.expansion(true), 2)
                val appended = store.expandResearchGraph(record.request.runId, "final", setOf("producer", planner.memberId), 3)!!
                assertEquals(2, appended.definition.members.count { it.context.containsKey(CollaborationCandidateEvolution.TASK) })
                val reviewer = appended.definition.members.single { it.context.containsKey(CollaborationCandidateEvolution.TASK) &&
                    JSONObject(it.context.getValue(CollaborationCandidateEvolution.TASK)).getString("member") == "reviewer-a" }
                // Simulate process loss after the workspace transaction, before its child-success event.
                f.execute(reviewer, "refuted")
                prefs.edit().putInt("seed_pid", android.os.Process.myPid()).putString("saved_node", reviewer.memberId).commit()
            } else {
                try {
                    assertNotEquals(prefs.getInt("seed_pid", -1), android.os.Process.myPid())
                    store.markInterrupted(record.request.runId, System.currentTimeMillis())
                    val checkpoint = requireNotNull(store.resumeCheckpoint(record.request.runId)) {
                        "The isolated fixture must perform the same interruption reconciliation as app startup"
                    }
                    assertEquals(2, checkpoint.completed.size)
                    val savedNode = checkpoint.definition.members.single { it.memberId == prefs.getString("saved_node", "") }
                    val task = JSONObject(savedNode.context.getValue(CollaborationCandidateEvolution.TASK))
                    val who = f.access.copy(nodeId = savedNode.memberId, personId = "reviewer-a", dependencyNodes = savedNode.dependsOnAgentIds)
                    assertNotNull(f.workspace.replayCandidateTask(who, task))
                    val prior = f.workspace.publicationRevisions(who, savedNode.memberId).single().toString()
                    val calls = CopyOnWriteArrayList<String>()
                    AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 3)).use { runtime ->
                        runtime.resume(checkpoint) { execution ->
                            val member = execution.member
                            assertFalse(member.memberId in checkpoint.completed)
                            calls += member.memberId
                            when {
                                member.context.containsKey(CollaborationCandidateEvolution.TASK) -> AgentSubagentOutput(f.execute(member))
                                CollaborationLiveGraph.planner(member) -> AgentSubagentOutput(f.expansion())
                                member.memberId == "slow" -> AgentSubagentOutput("slow-result")
                                else -> AgentSubagentOutput(f.assessment())
                            }
                        }.await()
                    }
                    assertEquals(calls.size, calls.distinct().size)
                    assertEquals(prior, f.workspace.publicationRevisions(who, savedNode.memberId).single().toString())
                    assertEquals("continue", store.snapshot(record.request.runId)!!.goalDisposition)
                } finally { fixture.clear(); prefs.edit().clear().commit() }
            }
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("candidate_phase", phase); putInt("process_id", android.os.Process.myPid())
            })
        }
    }

    private suspend fun complete(store: AgentTeamExecutionStore, id: String, output: String, sequence: Long) {
        store.append(AgentSubagentEvent(sequence, "candidate-run", id, AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult("candidate-run", id, "candidate-run", 1,
                AgentSubagentStatus.SUCCEEDED, output)))
    }
}
