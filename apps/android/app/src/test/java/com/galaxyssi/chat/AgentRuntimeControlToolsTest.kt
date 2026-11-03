package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class AgentRuntimeControlToolsTest {
    private val instance = "a".repeat(64)
    private fun observation(ready: Boolean = true, confirmed: Boolean = true, id: String = instance) =
        AgentRuntimeControlObservation(id, true,
            AgentRuntimeBridgeHealth(ready, reason = "Test observation", observationConfirmed = confirmed),
            AgentRuntimeLifecycleSnapshot(AgentRuntimeLifecyclePhase.DEGRADED), 123L)

    private fun registry(
        observe: () -> AgentRuntimeControlObservation = { observation() },
        control: (String, String) -> AgentRuntimeControlObservation = { _, _ -> observation() },
        maintenance: (() -> AgentRuntimeControlObservation) -> AgentRuntimeControlObservation? = { it() }
    ) = AgentNativeToolRegistry().registerAll(AgentRuntimeControlTools.definitions(observe, control, maintenance))

    private fun controlInput(operation: String = "start") = mapOf("operation" to operation, "expected_instance" to instance)

    @Test fun diagnosisDoesNotPerformLifecycleOperations() {
        val calls = AtomicInteger()
        val result = registry(control = { _, _ -> calls.incrementAndGet(); observation() })
            .invoke(AgentRuntimeControlTools.DIAGNOSE, emptyMap())
        assertTrue(result.toJson(), result.isSuccess)
        assertEquals(instance, result.output["runtime_instance"])
        assertEquals(123L, result.output["observed_at_epoch_ms"])
        assertEquals("cached_not_rehashed", result.output["pack_integrity"])
        assertEquals(0, calls.get())
    }

    @Test fun unconfirmedReadinessIsNeverAdvertisedAsReady() {
        val result = registry(observe = { observation(ready = true, confirmed = false) })
            .invoke(AgentRuntimeControlTools.DIAGNOSE, emptyMap())
        val health = result.output["health_observation"] as Map<*, *>
        assertEquals(false, health["confirmed"])
        assertEquals(false, health["ready"])
        assertEquals(true, result.output["engine_running"])
    }

    @Test fun lifecycleOperationUsesTheExactModelSelectionAndInstance() {
        val calls = mutableListOf<Pair<String, String>>()
        val result = registry(control = { operation, expected ->
            calls += operation to expected
            observation(id = "b".repeat(64))
        }).invoke(AgentRuntimeControlTools.CONTROL, controlInput("restart"))
        assertTrue(result.toJson(), result.isSuccess)
        assertEquals(listOf("restart" to instance), calls)
        assertEquals(true, result.output["live_state_may_be_lost"])
        assertEquals(false, result.output["workspace_files_reset"])
        assertEquals(false, result.output["side_effects_replayed"])
        assertEquals(true, result.output["requires_observation"])
    }

    @Test fun staleObservationIsReturnedAsNonterminalEvidence() {
        val result = registry(control = { _, _ -> throw AgentRuntimeControlFailure("runtime_instance_changed") })
            .invoke(AgentRuntimeControlTools.CONTROL, controlInput("restart"))
        assertEquals("runtime_instance_changed", result.error?.code)
        assertEquals(false, result.error?.details?.get("executed"))
        assertEquals(false, result.error?.details?.get("goal_terminal"))
    }

    @Test fun busyGuestIsNotRestarted() {
        val calls = AtomicInteger()
        val result = registry(control = { _, _ -> calls.incrementAndGet(); observation() }, maintenance = { null })
            .invoke(AgentRuntimeControlTools.CONTROL, controlInput("restart"))
        assertEquals("runtime_maintenance_busy", result.error?.code)
        assertEquals(0, calls.get())
        assertEquals(false, result.error?.details?.get("executed"))
    }

    @Test fun unsuccessfulStartPreservesDiagnosticOutputForTheModel() {
        val result = registry(control = { _, _ -> observation(ready = false, confirmed = false) })
            .invoke(AgentRuntimeControlTools.CONTROL, controlInput())
        assertEquals("runtime_not_ready", result.error?.code)
        assertEquals(instance, result.output["runtime_instance"])
        assertEquals(false, result.error?.details?.get("goal_terminal"))
    }

    @Test fun unexpectedOperationFailureIsNotMarkedUnexecutedOrAutomaticallyRetried() {
        val calls = AtomicInteger()
        val result = registry(control = { _, _ -> calls.incrementAndGet(); error("Transport lost") })
            .invoke(AgentRuntimeControlTools.CONTROL, controlInput("restart"))
        assertEquals("runtime_control_outcome_unknown", result.error?.code)
        assertEquals(true, result.error?.details?.get("outcome_unknown"))
        assertFalse(result.error!!.details.containsKey("executed"))
        assertEquals(1, calls.get())
    }

    @Test fun invalidLifecycleInputNeverReachesTheExecutor() {
        val calls = AtomicInteger()
        val tools = registry(control = { _, _ -> calls.incrementAndGet(); observation() })
        assertFalse(tools.invoke(AgentRuntimeControlTools.CONTROL, controlInput("reset_disk")).isSuccess)
        assertFalse(tools.invoke(AgentRuntimeControlTools.CONTROL, mapOf("operation" to "restart")).isSuccess)
        assertEquals(0, calls.get())
    }

    @Test fun lifecycleMutationAndReadOnlyDiagnosisHaveDifferentReplayContracts() {
        val definitions = AgentRuntimeControlTools.definitions({ observation() }, { _, _ -> observation() })
        val diagnose = definitions.single { it.descriptor.id == AgentRuntimeControlTools.DIAGNOSE }.descriptor
        val control = definitions.single { it.descriptor.id == AgentRuntimeControlTools.CONTROL }.descriptor
        assertEquals(AgentRuntimeControlTools.toolIds, definitions.map { it.descriptor.id }.toSet())
        assertFalse(diagnose.requiresEffectClaim)
        assertTrue(control.requiresEffectClaim)
        assertTrue(AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(control.id))
        assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(control.id))
    }

    @Test fun replayOfAnUnknownLifecycleOutcomeDoesNotRepeatTheOperation() {
        val calls = AtomicInteger()
        val tools = registry(control = { _, _ -> calls.incrementAndGet(); error("Transport lost after starting") })
        val context = AgentNativeToolInvocationContext(sessionId = "runtime-test", conversationId = "runtime-test",
            turnId = "turn-1", idempotencyKey = "lifecycle-operation-1")
        val first = tools.invoke(AgentRuntimeControlTools.CONTROL, controlInput("restart"), context)
        val replay = tools.invoke(AgentRuntimeControlTools.CONTROL, controlInput("restart"),
            context.copy(invocationId = "replay-invocation"))
        assertEquals("runtime_control_outcome_unknown", first.error?.code)
        assertEquals(first.error, replay.error)
        assertEquals(1, calls.get())
    }
}
