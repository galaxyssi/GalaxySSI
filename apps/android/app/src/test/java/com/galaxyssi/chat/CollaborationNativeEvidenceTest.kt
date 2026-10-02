package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationNativeEvidenceTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) { check(!fail); data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private val rows = Rows()
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node-a", "author-a")
    private val ledger = CollaborationEvidenceLedger(rows).apply { bind(101, access) }
    private val recorder = CollaborationNativeEvidence { ledger }
    private val context = AgentNativeToolInvocationContext(invocationId = "invocation", sessionId = "shared",
        conversationId = "group", turnId = "turn", collaborationSourceMessageId = 101)
    private val descriptor = AgentNativeToolDescriptor("phone.test.evidence", "1.0.0", "Fixture", "Fixture",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, setOf("fixture"), idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT)
    private fun registry(verifier: AgentNativeToolVerifier? = null,
                         operation: () -> AgentNativeToolExecutionResult = { AgentNativeToolExecutionResult.success(mapOf("original" to "observed")) }) =
        AgentNativeToolRegistry(observationRecorder = recorder).register(AgentNativeToolDefinition(
            descriptor, AgentNativeToolExecutor { operation() }, verifier))
    private fun saved(result: AgentNativeToolResult, reader: CollaborationWorkspaceAccess = access): JSONObject {
        val ref = result.collaborationObservation!!.receipt!!
        return ledger.read(reader, ref["evidence_id"] as String, ref["sha256"] as String)!!
    }

    @Test fun recordsActualNativeReceiptAndNotModelMetadata() {
        val result = registry { AgentNativeToolExecutionResult.success(mapOf("original" to "full ".repeat(4000)),
            metadata = mapOf("galaxyssi_evidence_receipt" to mapOf("evidence_id" to "forged"))) }
            .invoke(descriptor.id, mapOf("person_id" to "forged"), context)
        val observation = saved(result)
        assertEquals("android_native_tool", observation.getString("origin"))
        assertEquals("author-a", observation.getString("person_id"))
        assertEquals("returned", observation.getString("status"))
        assertEquals("execution_observed_not_claim_verified", observation.getString("trust"))
        val native = JSONObject(observation.getString("output_json"))
        assertEquals("full ".repeat(4000), native.getJSONObject("output").getString("original"))
        assertEquals("invocation", native.getJSONObject("receipt").getString("invocation_id"))
        assertFalse(native.has("galaxyssi_evidence_receipt"))
        assertNotEquals("forged", result.collaborationObservation!!.receipt!!["evidence_id"])
    }

    @Test fun ordinaryInvocationDoesNotOpenLedgerEvenWithSpoofedAttributes() {
        val native = AgentNativeToolRegistry(observationRecorder = CollaborationNativeEvidence { error("No storage access") })
            .register(AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor { AgentNativeToolExecutionResult.success() }))
        val result = native.invoke(descriptor.id, emptyMap(), context.copy(collaborationSourceMessageId = null,
            attributes = mapOf("collaboration_source" to "101", "person_id" to "author-a")))
        assertTrue(result.isSuccess)
        assertNull(result.collaborationObservation)
    }

    @Test fun sameSessionAndTurnDoNotMergeTwoMembers() {
        val second = access.copy(nodeId = "node-b", personId = "author-b")
        ledger.bind(102, second)
        val native = registry()
        val first = native.invoke(descriptor.id, emptyMap(), context)
        val next = native.invoke(descriptor.id, emptyMap(), context.copy(invocationId = "next", collaborationSourceMessageId = 102))
        assertEquals("author-b", saved(next, second).getString("person_id"))
        val ref = first.collaborationObservation!!.receipt!!
        assertNull(ledger.read(second, ref["evidence_id"] as String))
        assertNotNull(ledger.read(second.copy(dependencyNodes = setOf("node-a")), ref["evidence_id"] as String))
    }

    @Test fun missingWrongTurnAndRevokedBindingsNeverIssueReceipt() {
        listOf(context.copy(collaborationSourceMessageId = 999), context.copy(turnId = "another"),
            context.copy(conversationId = "another")).forEach {
            val result = registry().invoke(descriptor.id, emptyMap(), it)
            assertTrue(result.isSuccess)
            assertNull(result.collaborationObservation!!.receipt)
            assertEquals("dispatch_binding_unavailable", result.collaborationObservation!!.recording!!["reason"])
        }
        val revoked = CollaborationEvidenceLedger(rows) { false }
        val native = AgentNativeToolRegistry(observationRecorder = CollaborationNativeEvidence { revoked })
            .register(AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor { AgentNativeToolExecutionResult.success() }))
        assertNull(native.invoke(descriptor.id, emptyMap(), context).collaborationObservation!!.receipt)
    }

    @Test fun verificationFailureAndUnknownToolsAreFailedEvidence() {
        val failed = registry(AgentNativeToolVerifier { _, _ -> AgentNativeToolVerification(AgentNativeVerificationStatus.FAILED, "Mismatch") })
            .invoke(descriptor.id, emptyMap(), context)
        assertEquals(AgentNativeToolResultStatus.VERIFICATION_FAILED, failed.status)
        assertEquals("failed", saved(failed).getString("status"))
        val unknown = registry().invoke("phone.test.missing", emptyMap(), context.copy(invocationId = "unknown"))
        assertEquals("failed", saved(unknown).getString("status"))
    }

    @Test fun storageFailurePreservesCommittedEffectAndReplayDoesNotExecuteAgain() {
        var executions = 0
        val native = registry { executions++; AgentNativeToolExecutionResult.success() }
        rows.fail = true
        val first = native.invoke(descriptor.id, emptyMap(), context)
        assertTrue(first.isSuccess)
        assertNull(first.collaborationObservation!!.receipt)
        assertEquals(true, first.collaborationObservation!!.recording!!["do_not_reexecute"])
        rows.fail = false
        val replay = native.invoke(descriptor.id, emptyMap(), context)
        assertTrue(replay.receipt.replayed)
        assertEquals(1, executions)
        assertTrue(JSONObject(saved(replay).getString("output_json")).getJSONObject("receipt").getBoolean("replayed"))
    }

    @Test fun sameEffectKeyForDifferentMembersCannotBorrowAnExecution() {
        ledger.bind(102, access.copy(nodeId = "node-b", personId = "author-b"))
        var executions = 0
        val native = registry { executions++; AgentNativeToolExecutionResult.success() }
        val bound = context.copy(idempotencyKey = "same-model-key")
        val first = native.invoke(descriptor.id, emptyMap(), bound)
        val second = native.invoke(descriptor.id, emptyMap(), bound.copy(collaborationSourceMessageId = 102))
        assertFalse(first.receipt.replayed)
        assertFalse(second.receipt.replayed)
        assertEquals(2, executions)
        assertNotEquals(first.collaborationObservation!!.receipt, second.collaborationObservation!!.receipt)
    }

    @Test fun subsetKeepsRecorderAndIdenticalObservationIsIdempotent() {
        val native = registry().subset { true }
        val result = native.invoke(descriptor.id, emptyMap(), context)
        val replayedRecord = recorder.record(emptyMap(), context, result)!!
        assertEquals(result.collaborationObservation, replayedRecord)
        assertEquals(1, ledger.browse(access).first.size)
    }

    @Test fun receiptSurvivesResultCodecAndModelProjection() {
        val result = registry().invoke(descriptor.id, emptyMap(), context)
        val restored = JSONObject(result.toJson()).toNativeToolResult()!!
        assertEquals(result.collaborationObservation, restored.collaborationObservation)
        val projected = AgentModelToolResultContent("call", descriptor.id, "succeeded", nativeResult = restored.toJsonValue())
            .toModelJsonValue()
        assertEquals(result.collaborationObservation!!.receipt, projected["galaxyssi_evidence_receipt"])
    }

    @Test fun nativeLoopCarriesIdentityAndRecoversWithoutToolOrLedgerReplay() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var executions = 0
        val native = registry { executions++; AgentNativeToolExecutionResult.success() }
        val request = request()
        try {
            AgentModelToolLoop(AgentModelAdapter { if (it.round == 1) AgentModelResponse(toolCalls = listOf(
                AgentModelToolCall("call", descriptor.id))) else throw CancellationException("Fixture process loss") },
                native, journal = journal).run(request)
            fail("Expected interruption")
        } catch (_: CancellationException) { }
        assertEquals(1, ledger.browse(access).first.size)
        val resumed = AgentModelToolLoop(AgentModelAdapter {
            assertNotNull(it.messages.last().toolResult!!.toModelJsonValue()["galaxyssi_evidence_receipt"])
            AgentModelResponse("Recovered")
        }, registry { error("No tool replay") }, journal = journal).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
        assertEquals(1, executions)
        assertEquals(1, ledger.browse(access).first.size)
    }

    @Test fun anotherMemberCannotRestoreSameLoopCheckpoint() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        AgentModelToolLoop(AgentModelAdapter { AgentModelResponse("Done") }, registry(), journal = journal).run(request())
        try {
            AgentModelToolLoop(AgentModelAdapter { error("No request") }, registry(), journal = journal)
                .run(request().copy(collaborationSourceMessageId = 102))
            fail("Expected binding rejection")
        } catch (_: AgentModelLoopRecoveryException) { }
    }

    private fun request() = AgentModelToolLoopRequest("shared", "group", "turn", "task", "workspace",
        listOf(AgentModelMessage.user("Fixture")), loopId = "fixture-loop", collaborationSourceMessageId = 101)
}
