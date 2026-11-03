package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentSupervisedRecoveryBindingTest {
    private fun connector(locked: String = "true") = AgentAction("cloud", AgentActionKind.CALL_CONNECTOR,
        "DeepSeek", AgentRisk.LOW, AgentActionStatus.FAILED, "Test manual recovery", parameters = mapOf(
            "connector_id" to "cloud:deepseek", "connector_adapter_type" to "cloud-model-api",
            "model_id" to "user-selected-model", "manual_model_id" to "user-selected-model",
            "agent_reasoning_effort" to "high", "manual_target_locked" to locked,
            "routing_fallback_ids" to "codex,hermes", "auto_reroute_on_failure" to "true",
            "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
            INTERNAL_CONVERSATION_ID to "conversation", INTERNAL_TURN_ID to "turn"))

    @Test fun manualRecoveryNeverCallsTheRouterAndKeepsItsExactModelAndScope() {
        for (locked in listOf("true", "TRUE")) {
            val original = connector(locked)
            var recovered = original
            repeat(5) {
                recovered = AgentSupervisedRecoveryBinding.resolve(recovered) { error("Manual selection rerouted") }
            }
            assertEquals(original.target, recovered.target)
            for (key in listOf("connector_id", "connector_adapter_type", "model_id", "manual_model_id",
                    "agent_reasoning_effort", INTERNAL_CONVERSATION_ID, INTERNAL_TURN_ID)) {
                assertEquals(key, original.parameters[key], recovered.parameters[key])
            }
            assertEquals("true", recovered.parameters["manual_target_locked"])
            assertEquals("false", recovered.parameters["auto_reroute_on_failure"])
            assertEquals("", recovered.parameters["routing_fallback_ids"])
            assertTrue(recovered.isSupervisedProjectConnector())
        }
    }

    @Test fun autoRecoveryStillUsesTheSuppliedRouter() {
        var calls = 0
        val fallback = connector("false").copy(target = "Codex")
        val recovered = AgentSupervisedRecoveryBinding.resolve(connector("false")) { calls++; fallback }
        assertEquals(1, calls)
        assertSame(fallback, recovered)
    }

    @Test fun legacyRecoveryRecoversTheOriginalManualBindingWithinTheTurn() {
        val original = connector()
        val damaged = connector("false").copy(target = "Codex", parameters = original.parameters + mapOf(
            "manual_target_locked" to "false", "connector_id" to "codex", "manual_model_id" to "wrong-model"))
        val recovered = AgentSupervisedRecoveryBinding.resolve(damaged, listOf(original, damaged)) {
            error("Old manual request must not reroute")
        }
        assertEquals("cloud:deepseek", recovered.parameters["connector_id"])
        assertEquals("user-selected-model", recovered.parameters["manual_model_id"])
        assertEquals("true", recovered.parameters["manual_target_locked"])
    }
}
