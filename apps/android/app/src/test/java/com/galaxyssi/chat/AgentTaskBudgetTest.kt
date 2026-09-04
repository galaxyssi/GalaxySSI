package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTaskBudgetTest {
    @Test
    fun builtInProfilesMatchTheCrossPlatformContract() {
        val adaptive = AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ADAPTIVE)
        val fast = AgentTaskBudget.forProfile(AgentTaskBudgetProfile.FAST)
        val economy = AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ECONOMY)
        val private = AgentTaskBudget.forProfile(AgentTaskBudgetProfile.PRIVATE)

        assertEquals(0L, adaptive.maxElapsedSeconds)
        assertEquals(0L, adaptive.maxCostMicros)
        assertEquals(0L, fast.maxElapsedSeconds)
        assertEquals(0L, fast.maxInputTokens)
        assertEquals(0L, economy.maxCostMicros)
        assertEquals(0L, economy.maxNetworkBytes)
        assertFalse(private.allowCloud)
        assertFalse(private.allowPaidProviders)
        assertEquals(AgentTaskNetworkPolicy.TRUSTED_ONLY, private.networkPolicy)
    }

    @Test
    fun taskBudgetJsonRoundTripPreservesEveryLimit() {
        val original = AgentTaskBudget(
            profile = AgentTaskBudgetProfile.CUSTOM,
            maxElapsedSeconds = 777,
            maxCostMicros = 123_456,
            maxInputTokens = 12_345,
            maxOutputTokens = 6_789,
            maxNetworkBytes = 42 * AgentTaskBudget.MIB,
            minimumBatteryPercent = 27,
            maxMemoryBytes = 900 * AgentTaskBudget.MIB,
            networkPolicy = AgentTaskNetworkPolicy.UNMETERED_ONLY,
            allowCloud = true,
            allowPaidProviders = false
        )

        val restored = AgentTaskBudgetJsonCodec.decode(
            AgentTaskBudgetJsonCodec.encode(original)
        )

        assertEquals(original, restored)
    }

    @Test
    fun resourceCountersNeverTerminateAUserTask() {
        val cases = listOf(
            Triple(
                AgentTaskBudget(maxElapsedSeconds = 1),
                AgentTaskBudgetUsage(elapsedMillis = 1_001),
                AgentTaskBudgetLimit.TIME
            ),
            Triple(
                AgentTaskBudget(maxCostMicros = 10),
                AgentTaskBudgetUsage(costMicros = 11),
                AgentTaskBudgetLimit.COST
            ),
            Triple(
                AgentTaskBudget(maxInputTokens = 10),
                AgentTaskBudgetUsage(inputTokens = 11),
                AgentTaskBudgetLimit.INPUT_TOKENS
            ),
            Triple(
                AgentTaskBudget(maxOutputTokens = 10),
                AgentTaskBudgetUsage(outputTokens = 11),
                AgentTaskBudgetLimit.OUTPUT_TOKENS
            ),
            Triple(
                AgentTaskBudget(maxNetworkBytes = 10),
                AgentTaskBudgetUsage(networkBytes = 11),
                AgentTaskBudgetLimit.NETWORK
            ),
            Triple(
                AgentTaskBudget(maxMemoryBytes = 10),
                AgentTaskBudgetUsage(peakMemoryBytes = 11),
                AgentTaskBudgetLimit.MEMORY
            )
        )

        cases.forEach { (budget, usage, _) ->
            val decision = AgentTaskBudgetPolicy.evaluate(budget, usage)
            assertTrue(decision.allowed)
            assertEquals(null, decision.limit)
        }
    }

    @Test
    fun batteryAndNetworkChecksUseTheCurrentEnvironment() {
        val lowBattery = AgentTaskBudgetPolicy.evaluate(
            AgentTaskBudget(minimumBatteryPercent = 20),
            AgentTaskBudgetUsage(),
            AgentTaskBudgetEnvironment(batteryPercent = 19, charging = false)
        )
        val charging = AgentTaskBudgetPolicy.evaluate(
            AgentTaskBudget(minimumBatteryPercent = 20),
            AgentTaskBudgetUsage(),
            AgentTaskBudgetEnvironment(batteryPercent = 1, charging = true)
        )
        val trusted = AgentTaskBudgetPolicy.evaluate(
            AgentTaskBudget(networkPolicy = AgentTaskNetworkPolicy.TRUSTED_ONLY),
            AgentTaskBudgetUsage(),
            AgentTaskBudgetEnvironment(networkAvailable = true),
            networkRequired = true,
            trustedNetworkTarget = true
        )
        val untrusted = AgentTaskBudgetPolicy.evaluate(
            AgentTaskBudget(networkPolicy = AgentTaskNetworkPolicy.TRUSTED_ONLY),
            AgentTaskBudgetUsage(),
            AgentTaskBudgetEnvironment(networkAvailable = true),
            networkRequired = true,
            trustedNetworkTarget = false
        )

        assertTrue(lowBattery.allowed)
        assertTrue(charging.allowed)
        assertTrue(trusted.allowed)
        assertEquals(AgentTaskBudgetLimit.NETWORK, untrusted.limit)
    }

    @Test
    fun lowBatteryAndMemoryTelemetryNeverBlocksTransport() {
        val decision = AgentTaskBudgetPolicy.evaluate(
            budget = AgentTaskBudget(
                minimumBatteryPercent = 80,
                maxMemoryBytes = 1
            ),
            usage = AgentTaskBudgetUsage(peakMemoryBytes = 1024),
            environment = AgentTaskBudgetEnvironment(
                batteryPercent = 5,
                charging = false,
                appMemoryBytes = 1024,
                networkAvailable = true
            ),
            networkRequired = true,
            trustedNetworkTarget = true
        )

        assertTrue(decision.allowed)
    }

    @Test
    fun executionLoopPersistsResourceUsageWithoutTerminatingTheTask() {
        val loop = AgentExecutionLoop.create { 1_000L }
        loop.start(
            taskId = "budgeted-task",
            budget = AgentExecutionLoopBudget(),
            taskBudget = AgentTaskBudget(
                profile = AgentTaskBudgetProfile.CUSTOM,
                maxInputTokens = 10,
                maxOutputTokens = 20
            )
        )

        val updated = loop.recordTaskBudgetUsage(
            inputTokens = 11,
            outputTokens = 3,
            estimated = true
        )
        val restored = AgentExecutionLoopJsonCodec.decode(
            AgentExecutionLoopJsonCodec.encode(updated.snapshot)
        )

        assertEquals(AgentExecutionLoopPhase.PLAN, updated.phase)
        assertEquals(11L, restored?.taskBudgetUsage?.inputTokens)
        assertEquals(3L, restored?.taskBudgetUsage?.outputTokens)
        assertTrue(restored?.taskBudgetUsage?.usageEstimated == true)
        assertTrue(restored?.budgetFailure.isNullOrBlank())
    }
}
