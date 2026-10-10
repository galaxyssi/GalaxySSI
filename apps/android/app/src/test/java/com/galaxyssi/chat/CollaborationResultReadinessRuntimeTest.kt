package com.galaxyssi.chat

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResultReadinessRuntimeTest {
    private class Rows : CollaborationWorkspaceRows {
        private val data = ConcurrentHashMap<String, String>()
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) =
            data.keys.filter { it.startsWith(prefix) && it > after }.sorted().take(limit)
    }

    @Test fun requiredImportReleasesDependentWorkWithoutWaitingForUnrelatedArchive(): Unit = runBlocking {
        withTimeout(15_000) {
            val source = CollaborationEvidenceLedger(Rows())
            val phone = CollaborationEvidenceLedger(Rows())
            val workspace = CollaborationResearchWorkspace(Rows(), evidence = phone::references)
            val stored = ConcurrentHashMap<String, String>()
            val originalPreserved = CompletableDeferred<CollaborationWorkspaceAccess>()
            val waitingForRequired = CompletableDeferred<Unit>()
            val requiredImported = CompletableDeferred<Unit>()
            val independentFinished = CompletableDeferred<Unit>()
            val reviewerStarted = AtomicBoolean()
            val archiveStillPending = AtomicBoolean(true)
            val memberContext = mapOf("collaboration_group_id" to "group", CollaborationResearchWorkflow.STAGE to "EXECUTE")
            val producer = AgentTeamMember("desktop:codex", AgentDeliveryMode.OBSERVE, instanceId = "producer",
                context = memberContext + (CollaborationResearchWorkflow.PERSON to "producer"))
            val independent = producer.copy(instanceId = "independent",
                context = memberContext + (CollaborationResearchWorkflow.PERSON to "independent"))
            val reviewer = producer.copy(instanceId = "reviewer", deliveryMode = AgentDeliveryMode.RESPOND,
                dependsOnAgentIds = setOf("producer"),
                context = memberContext + (CollaborationResearchWorkflow.PERSON to "reviewer"))
            val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = "Compare observed alternatives")
            fun observation(ledger: CollaborationEvidenceLedger, access: CollaborationWorkspaceAccess) =
                ledger.record(access, "compute", "calculate", "{}", "{\"status\":\"success\",\"value\":7}", 1, 2)
            val finalizer = CollaborationResultFinalizer(workspace, { execution, raw ->
                stored[execution.member.memberId] = raw
                originalPreserved.complete(CollaborationWorkspaceAccess.from(execution))
                "archive"
            })
            AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore(), AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                val handle = runtime.start(AgentTeamDefinition("readiness-team", reviewer.agentId,
                    listOf(producer, independent, reviewer), primaryInstanceId = reviewer.memberId), request) { execution ->
                    val access = CollaborationWorkspaceAccess.from(execution)
                    when (execution.member.memberId) {
                        "producer" -> {
                            val ref = observation(source, access)
                            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Observed alternative")
                                .put("workspace", JSONArray().put(JSONObject().put("id", "result").put("kind", "artifact")
                                    .put("title", "Measured result").put("body", JSONObject().put("content", "Measurement is 7"))
                                    .put("observations", JSONArray().put(ref)))).toString()
                            val gate = CollaborationResultEvidence.inspect(raw)
                            finalizer.finishWhenReady(execution, AgentSubagentOutput(raw)) {
                                assertEquals(raw, stored["producer"])
                                execution.suspendExecutionPermit {
                                    while (gate.awaiting(archiveStillPending::get) { phone.read(access, it) }) {
                                        waitingForRequired.complete(Unit)
                                        requiredImported.await()
                                    }
                                }
                            }
                        }
                        "independent" -> {
                            waitingForRequired.await()
                            independentFinished.complete(Unit)
                            AgentSubagentOutput("Independent work proceeded")
                        }
                        "reviewer" -> {
                            reviewerStarted.set(true)
                            assertTrue(archiveStillPending.get())
                            val version = workspace.browse(access).revisions.single()
                            val saved = workspace.read(access, version.getString("object_id"), version.getInt("revision"))!!
                            assertEquals("Measurement is 7", saved.getJSONObject("body").getString("content"))
                            assertEquals("member_reported_not_verified", saved.getString("evidence_state"))
                            AgentSubagentOutput("Original is available for review; no goal acceptance claimed")
                        }
                        else -> error("Unexpected assignment")
                    }
                }
                try {
                    val access = originalPreserved.await()
                    independentFinished.await()
                    assertFalse(reviewerStarted.get())
                    assertTrue(workspace.browse(access).revisions.isEmpty())
                    observation(phone, access)
                    requiredImported.complete(Unit)
                    val result = handle.await()
                    assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.subagentResult.status)
                    assertTrue(reviewerStarted.get())
                    assertTrue(archiveStillPending.get())
                    assertEquals(1, stored.size)
                } finally {
                    requiredImported.complete(Unit)
                    handle.cancel()
                }
            }
        }
    }
}
