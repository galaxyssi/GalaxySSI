package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentBrowserInterruptionPolicyTest {
    private val scope = "a".repeat(64)
    private val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "browser"), "generation", scope,
        "session", "conversation", "turn", "caller", "workspace", "browser", "page", "handoff", "active",
        runWorkspaceId = "run", hostProcessId = "same-host")
    private val snapshot = mapOf("operation" to "human_control_execute", "action" to mapOf("operation" to "snapshot"))

    @Test fun explicitSessionLossSettlesOnlyTheRecordedHandoff() {
        for (code in listOf("session_lost", "session_closed", "session_not_found", "browser_closed", "browser_user_handoff_invalid")) {
            val event = AgentBrowserInterruptionPolicy.observed(record, code, snapshot)!!
            assertEquals("interrupted", event.state)
            assertEquals(code, event.interruptionCode)
            assertEquals(record.hostProcessId, event.hostProcessId)
            assertEquals(record.generation, event.generation)
            assertEquals(record.handoffId, event.handoffId)
            assertTrue(event.pendingRunWake)
            assertTrue(record.permitsSameGeneration(event))
            assertFalse(event.permitsSameGeneration(record.copy(state = "returned")))
            assertEquals(event, AgentBrowserUserRequest.fromJson(event.toJson()))
        }
    }

    @Test fun timeoutReadinessDriverUpgradeAndMissingDependenciesDoNotProveSessionLoss() {
        for (code in listOf("browser_result_unobserved", "browser_readiness_unobserved", "browser_driver_changed",
            "browser_start_pending", "browser_runtime_missing", "browser_operation_cancelled", "element_not_found",
            "page_not_found", "TimeoutError", "untrusted_error")) {
            assertNull(code, AgentBrowserInterruptionPolicy.observed(record, code, snapshot))
        }
    }

    @Test fun malformedUserActionCannotBeMistakenForLostControl() {
        assertNull(AgentBrowserInterruptionPolicy.observed(record, "browser_user_handoff_invalid",
            mapOf("operation" to "human_control_execute", "action" to emptyMap<String, String>())))
        for (operation in listOf("human_control_state", "human_control_finish")) {
            assertNotNull(AgentBrowserInterruptionPolicy.observed(record, "browser_user_handoff_invalid",
                mapOf("operation" to operation)))
        }
    }

    @Test fun requestedReturnedAndInterruptedRecordsCannotBeSettledAgain() {
        for (state in listOf("requested", "returned", "interrupted"))
            assertNull(AgentBrowserInterruptionPolicy.observed(record.copy(state = state), "session_lost", snapshot))
        assertNull(AgentBrowserInterruptionPolicy.observed(record.copy(handoffId = ""), "session_lost", snapshot))
    }

    @Test fun interruptionDoesNotInventLoginOrBusinessSuccess() {
        val message = AgentBrowserInterruptionPolicy.message("session_lost")
        assertTrue(message.contains("session_lost"))
        assertFalse(message.contains("App host restarted"))
        assertTrue(message.contains("business results are unconfirmed"))
        assertTrue(message.contains("no browser mutation was replayed"))
        assertTrue(AgentBrowserInterruptionPolicy.message("browser_host_restarted").contains("not proved lost"))
        assertFalse(AgentBrowserInterruptionPolicy.valid("arbitrary"))
    }

    @Test fun explicitOwnerStopIsADurableRetirementNotAnObservedSessionFailure() {
        assertTrue(AgentBrowserInterruptionPolicy.valid("browser_owner_stopped"))
        val stopped = record.copy(state = "interrupted", interruptionCode = "browser_owner_stopped")
        assertTrue(record.permitsSameGeneration(stopped))
        assertFalse(stopped.permitsSameGeneration(record.copy(state = "returned")))
        assertEquals(stopped, AgentBrowserUserRequest.fromJson(stopped.toJson()))
        assertNull(AgentBrowserInterruptionPolicy.observed(record, "browser_owner_stopped", snapshot))
        assertTrue(AgentBrowserInterruptionPolicy.message("browser_owner_stopped").contains("Do not resume or replay"))
    }
}
