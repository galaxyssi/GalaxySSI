package com.galaxyssi.chat

import android.os.Process
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentConnectorFallbackDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun encryptedCheckpointKeepsSelectedAgentAndAttemptHistory() {
        val key = "task:failover-test-${UUID.randomUUID()}"
        val store = SharedPreferencesAgentSessionStore(context, key)
        try {
            store.save(snapshot(key))
            assertRecovered(requireNotNull(SharedPreferencesAgentSessionStore(context, key).load()))
        } finally {
            store.clear()
        }
    }

    @Test fun independentTurnsDoNotShareFailoverHistory() {
        val firstKey = "task:failover-test-${UUID.randomUUID()}"
        val secondKey = "task:failover-test-${UUID.randomUUID()}"
        val first = SharedPreferencesAgentSessionStore(context, firstKey)
        val second = SharedPreferencesAgentSessionStore(context, secondKey)
        try {
            first.save(snapshot(firstKey))
            second.save(snapshot(secondKey, setOf("other-resource")))
            assertRecovered(requireNotNull(first.load()))
            assertEquals(setOf("other-resource"), AgentConnectorFallbackAction.attempted(second.load()!!.lastActionResult!!.metadata))
        } finally {
            first.clear()
            second.clear()
        }
    }

    @Test fun reopenedCheckpointDoesNotRetryPermanentCloudFailure() {
        val key = "task:failover-test-${UUID.randomUUID()}"
        val store = SharedPreferencesAgentSessionStore(context, key)
        try {
            store.save(snapshot(key))
            val pending = SharedPreferencesAgentSessionStore(context, key).load()!!.lastActionResult!!
            val attempted = AgentConnectorFallbackAction.attempted(pending.metadata)
            val candidates = AgentConnectorFallbackTrail.mergeAvailable(
                listOf("cloud", "local"), listOf("cloud", "hermes", "codex", "local"), "codex", attempted
            )
            assertEquals(listOf("local"), candidates)
        } finally {
            store.clear()
        }
    }

    @Test fun failedAgentDoesNotPutItsHealthyDesktopIntoCooldown() {
        val id = "test-failover-${UUID.randomUUID()}"
        val health = AgentResourceHealthStore(context)
        val prefs = context.getSharedPreferences("galaxyssi_agent_resource_health", 0)
        try {
            health.recordFailureDomainTimeout("domain:$id", 45_000)
            health.record("target:$id", false, 45_000)
            assertTrue(health.snapshot("domain:$id").circuitOpen)
            health.markAvailable("domain:$id")
            assertFalse(health.snapshot("domain:$id").circuitOpen)
            assertEquals(1, health.snapshot("target:$id").failures)
            assertTrue(AgentConnectorFailureScope.permitsFallback(
                mapOf("failure_domain" to id, "timeout_stage" to "NOT_RUNNING"), id
            ))
        } finally {
            // Only namespaced test health rows are touched; no configured provider is changed.
            prefs.edit().remove("domain:$id").remove("target:$id").commit()
        }
    }

    @Test fun persistFailoverBeforeProcessDeath() {
        val key = restartKey()
        SharedPreferencesAgentSessionStore(context, key).save(snapshot(key).copy(
            currentGoal = "failover-process:${Process.myPid()}"
        ))
        Log.i("FallbackRecoveryTest", "saved pid=${Process.myPid()} key=$key")
    }

    @Test fun recoverFailoverAfterProcessDeath() {
        val key = restartKey()
        val store = SharedPreferencesAgentSessionStore(context, key)
        try {
            val recovered = requireNotNull(store.load())
            assertNotEquals("failover-process:${Process.myPid()}", recovered.currentGoal)
            assertRecovered(recovered)
            Log.i("FallbackRecoveryTest", "recovered pid=${Process.myPid()} key=$key")
        } finally {
            store.clear()
        }
    }

    private fun restartKey(): String {
        val id = InstrumentationRegistry.getArguments().getString("failoverRecoveryId").orEmpty()
        assumeTrue(id.matches(Regex("failover-process-[0-9a-f-]{36}")))
        return "task:$id"
    }

    private fun snapshot(key: String, attempted: Set<String> = setOf("cloud", "hermes")): AgentSessionSnapshot {
        val original = AgentAction("dispatch", AgentActionKind.CALL_CONNECTOR, "Cloud", AgentRisk.LOW,
            AgentActionStatus.WAITING_RESPONSE, "Test failover", requiresConfirmation = false)
        val selection = AgentConnectorFallbackSelection("codex", listOf("local"), emptyList(), emptySet(), attempted)
        val retry = AgentConnectorFallbackAction.prepare(original, selection, null)
        val screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent")
        return AgentSessionSnapshot(
            sessionId = key, phase = AgentPhase.PLANNING, currentGoal = "Test failover persistence",
            currentScreen = screen,
            currentPlan = AgentPlan("Test failover", screen, emptyList(), listOf(retry)),
            auditTrail = emptyList(),
            lastActionResult = AgentActionResult("dispatch", false, "Previous resource failed",
                AgentConnectorFallbackAction.resultMetadata(retry) + mapOf("awaiting_response" to "false")),
            updatedAtMillis = System.currentTimeMillis()
        )
    }

    private fun assertRecovered(snapshot: AgentSessionSnapshot) {
        val action = snapshot.currentPlan!!.actions.single()
        assertEquals("codex", action.parameters["connector_id"])
        assertEquals(AgentActionStatus.PROPOSED, action.status)
        assertEquals(listOf("codex", "local"), AgentConnectorFallbackAction.dispatchIds(action))
        assertEquals(setOf("cloud", "hermes"), AgentConnectorFallbackAction.attempted(snapshot.lastActionResult!!.metadata))
    }
}
