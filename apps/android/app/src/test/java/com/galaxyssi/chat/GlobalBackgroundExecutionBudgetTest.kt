package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GlobalBackgroundExecutionBudgetTest {
    @Test
    fun `healthy unmetered environment allows every background work kind`() {
        val environment = healthyEnvironment()

        GlobalBackgroundWorkKind.values().forEach { kind ->
            assertTrue(decide(kind, environment).allowed)
        }
    }

    @Test
    fun `power state never defers background work`() {
        GlobalBackgroundWorkKind.values().forEach { kind ->
            val decision = decide(kind, healthyEnvironment().copy(powerSaveMode = true))

            assertTrue(decision.allowed)
            assertEquals(GlobalBackgroundDeferralReason.NONE, decision.reason)
        }
    }

    @Test
    fun `low battery never defers background work`() {
        val environment = healthyEnvironment().copy(batteryPercent = 1, charging = false)
        GlobalBackgroundWorkKind.values().forEach { kind ->
            assertTrue(decide(kind, environment).allowed)
        }
    }

    @Test
    fun `metered network never defers background work`() {
        val metered = healthyEnvironment().copy(networkMetered = true)

        GlobalBackgroundWorkKind.values().forEach { kind ->
            val decision = decide(kind, metered)
            assertTrue(decision.allowed)
            assertEquals(GlobalBackgroundDeferralReason.NONE, decision.reason)
        }
    }

    @Test
    fun `offline state does not add a scheduler constraint`() {
        val offline = healthyEnvironment().copy(
            networkAvailable = false,
            networkValidated = false
        )

        GlobalBackgroundWorkKind.values().forEach { kind ->
            val decision = decide(kind, offline)
            assertTrue(decision.allowed)
            assertEquals(GlobalBackgroundDeferralReason.NONE, decision.reason)
        }
    }

    @Test
    fun `explicit user action can bypass network scheduling`() {
        val constrained = healthyEnvironment().copy(
            batteryPercent = 5,
            powerSaveMode = true,
            networkMetered = true
        )

        assertTrue(decide(GlobalBackgroundWorkKind.COGNITION, constrained).allowed)
        val forced = GlobalBackgroundExecutionBudgetPolicy.decide(
            kind = GlobalBackgroundWorkKind.RESEARCH,
            environment = constrained,
            settings = GlobalAgentSettings(),
            nowMillis = NOW,
            explicitUserOverride = true
        )
        assertTrue(forced.allowed)
        assertEquals(NOW, forced.nextEligibleAtMillis)
    }

    private fun decide(
        kind: GlobalBackgroundWorkKind,
        environment: AgentRuntimeEnvironment,
        settings: GlobalAgentSettings = GlobalAgentSettings()
    ): GlobalBackgroundExecutionDecision = GlobalBackgroundExecutionBudgetPolicy.decide(
        kind = kind,
        environment = environment,
        settings = settings,
        nowMillis = NOW
    )

    private fun healthyEnvironment() = AgentRuntimeEnvironment(
        batteryPercent = 80,
        charging = false,
        powerSaveMode = false,
        networkAvailable = true,
        networkValidated = true,
        networkMetered = false
    )

    private companion object {
        const val NOW = 1_000_000L
    }
}
