package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentConnectorReceiptAdmissionTest {
    private val pending = AgentActionResult("dispatch", false, "Awaiting", mapOf(
        "source_message_id" to "12", "contact_id" to "peer", "resource_location" to "desktop",
        "conversation_id" to "conversation", "remote_task_id" to "task", "turn_id" to "turn"))
    private val saved = AgentSessionSnapshot("session", AgentPhase.WAITING_RESPONSE, "Goal", ScreenContext("", pageTitle = ""),
        null, emptyList(), pending, updatedAtMillis = 100)

    @Test fun matchingWaitAndRecoverableTimeoutRetainExistingAdmission() {
        assertTrue(admit())
        assertTrue(admit(saved.copy(phase = AgentPhase.FAILED, lastActionResult = pending.copy(
            metadata = pending.metadata + ("timeout_stage" to "not_accepted")))))
        assertFalse(admit(saved.copy(phase = AgentPhase.COMPLETED)))
        assertFalse(admit(saved.copy(phase = AgentPhase.CANCELLED)))
        assertFalse(admit(saved.copy(lastActionResult = null)))
    }

    @Test fun wrongReceiptIsRejectedBeforeAnAgentIsConstructed() {
        assertFalse(admit(source = 13))
        assertFalse(admit(contact = "other"))
        assertFalse(admit(conversation = "other"))
        assertFalse(admit(turn = "other"))
        assertFalse(admit(task = "other"))
    }

    @Test fun knownDispatchConflictStillReachesTheDurableRepairPath() {
        assertTrue(admit(saved.copy(phase = AgentPhase.FAILED, lastActionResult = pending.copy(
            metadata = mapOf("error_code" to "idempotency_key_conflict")))))
    }

    @Test fun cancelledOrMissingSessionsNeverConstructAnAgent() {
        var created = 0
        repeat(1_000) {
            assertNull(AgentConnectorReceiptAdmission.restoreCandidate(saved.copy(phase = AgentPhase.CANCELLED)) { created++ })
            assertNull(AgentConnectorReceiptAdmission.restoreCandidate(null) { created++ })
        }
        assertEquals(0, created)
    }

    @Test fun preflightKeepsNonCancelledRecoveryAndLiveReceiptValidation() {
        AgentPhase.entries.filter { it != AgentPhase.CANCELLED }.forEach { phase ->
            assertEquals("runtime", AgentConnectorReceiptAdmission.restoreCandidate(saved.copy(phase = phase)) { "runtime" })
        }
    }

    private fun admit(session: AgentSessionSnapshot = saved, source: Long = 12, contact: String = "peer",
        conversation: String = "conversation", turn: String = "turn", task: String = "task") =
        AgentConnectorReceiptAdmission.saved(session, source, contact, conversation, turn, task)
}
