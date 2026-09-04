package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRemoteReputationTest {
    private val desktopId = "desktop_0123456789abcdef"
    private val taskId = "task-123"
    private val contactId = "$desktopId:codex"

    @Test
    fun decodesDesktopReceiptAndPreservesCanonicalFieldOrder() {
        val json = receiptJson()

        val receipt = AgentReputationWireCodec.decodeReceipt(json)

        requireNotNull(receipt)
        assertEquals(contactId, receipt.agentId)
        assertEquals(setOf(AgentCapability.CHAT, AgentCapability.CODE), receipt.capabilities)
        assertEquals(AgentReputationReceiptProvenance.HOST_OBSERVED, receipt.provenance)
        val canonical = String(receipt.canonicalPayload(), Charsets.UTF_8)
        val taskHash = agentReputationSha256(taskId.toByteArray(Charsets.UTF_8))
        assertTrue(
            canonical.startsWith("""{"actual_cost_units":0,"agent_id":"$contactId"""")
        )
        assertTrue(
            canonical.endsWith(
                "\"started_at_millis\":1000,\"task_id_hash\":\"$taskHash\",\"version\":1}"
            )
        )
        assertEquals(
            "fe6995403d63a8ca06ab70ae20d0e3b62749d3ab9eac8b2a2e3e62e775ecf4e7",
            agentReputationSha256(canonical.toByteArray(Charsets.UTF_8))
        )
    }

    @Test
    fun bindsReceiptToPairedDesktopAgentAndTask() {
        val receipt = requireNotNull(AgentReputationWireCodec.decodeReceipt(receiptJson()))
        val envelope = JSONObject()
            .put("desktop_id", desktopId)
            .put("task_id", taskId)
            .put("agent_id", "codex")
            .put("contact_id", contactId)

        assertNull(AgentRemoteReputation.bindingFailure(envelope, receipt))
        assertEquals(
            "receipt_binding_invalid",
            AgentRemoteReputation.bindingFailure(
                envelope.put("task_id", "other-task"),
                receipt
            )
        )
    }

    @Test
    fun rejectsCrossDesktopOrCrossAgentReputationClaims() {
        val receipt = requireNotNull(AgentReputationWireCodec.decodeReceipt(receiptJson()))
        val envelope = JSONObject()
            .put("desktop_id", "desktop_fedcba9876543210")
            .put("task_id", taskId)
            .put("agent_id", "codex")
            .put("contact_id", "desktop_fedcba9876543210:codex")

        assertEquals(
            "receipt_binding_invalid",
            AgentRemoteReputation.bindingFailure(envelope, receipt)
        )
    }

    private fun receiptJson(): JSONObject = JSONObject()
        .put("version", 1)
        .put("receipt_id", "receipt-1")
        .put("run_id", "run-1")
        .put("task_id_hash", agentReputationSha256(taskId.toByteArray(Charsets.UTF_8)))
        .put("agent_id", contactId)
        .put("installation_id", desktopId)
        .put("executor_failure_domain", desktopId)
        .put("capabilities", JSONArray(listOf("CHAT", "CODE")))
        .put("outcome", "SUCCEEDED")
        .put("provenance", "HOST_OBSERVED")
        .put("started_at_millis", 1_000L)
        .put("completed_at_millis", 2_000L)
        .put("deadline_at_millis", 0L)
        .put("estimated_cost_units", 0)
        .put("actual_cost_units", 0)
        .put("output_hash", "b".repeat(64))
        .put("evidence_hash", "c".repeat(64))
        .put("signer_id", desktopId)
        .put("signature_key_id", "a".repeat(64))
        .put("signature", "signature")
}
