package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class VoiceRealtimeHealthPolicyTest {
    @Test
    fun activeRuntimeWinsWhenDependenciesAreReady() {
        val snapshot = evaluate(record = VoiceRuntimeHealthRecord(active = true))

        assertEquals(VoiceHealthState.ACTIVE, snapshot[VoiceHealthComponent.ASR].state)
    }

    @Test
    fun disabledWakeHealthIsExplicit() {
        val snapshot = evaluate(enabled = false)

        assertEquals(VoiceHealthState.DISABLED, snapshot[VoiceHealthComponent.ASR].state)
        assertEquals(VoiceHealthIssue.DISABLED, snapshot[VoiceHealthComponent.ASR].issue)
    }

    @Test
    fun missingDependencyBlocksBeforeRuntimeState() {
        val snapshot = evaluate(
            dependency = VoiceHealthDependency(
                ready = false,
                issue = VoiceHealthIssue.MODEL_MISSING
            ),
            record = VoiceRuntimeHealthRecord(active = true)
        )

        assertEquals(VoiceHealthState.BLOCKED, snapshot[VoiceHealthComponent.ASR].state)
        assertEquals(VoiceHealthIssue.MODEL_MISSING, snapshot[VoiceHealthComponent.ASR].issue)
    }

    @Test
    fun recentFailureProducesDegradedHealth() {
        val now = 500_000L
        val snapshot = evaluate(
            record = VoiceRuntimeHealthRecord(
                lastFailureAtMillis = now - 2_000L,
                lastFailureReason = "recognizer busy"
            ),
            nowMillis = now
        )

        assertEquals(VoiceHealthState.DEGRADED, snapshot[VoiceHealthComponent.ASR].state)
        assertEquals(VoiceHealthIssue.RECENT_FAILURE, snapshot[VoiceHealthComponent.ASR].issue)
    }

    @Test
    fun newerSuccessRecoversRecentFailure() {
        val now = 500_000L
        val snapshot = evaluate(
            record = VoiceRuntimeHealthRecord(
                lastFailureAtMillis = now - 4_000L,
                lastSuccessAtMillis = now - 1_000L
            ),
            nowMillis = now
        )

        assertEquals(VoiceHealthState.HEALTHY, snapshot[VoiceHealthComponent.ASR].state)
    }

    @Test
    fun staleSuccessReturnsToReadyInsteadOfClaimingPermanentHealth() {
        val now = VoiceRealtimeHealthPolicy.SUCCESS_FRESHNESS_MS + 50_000L
        val snapshot = evaluate(
            record = VoiceRuntimeHealthRecord(lastSuccessAtMillis = 1L),
            nowMillis = now
        )

        assertEquals(VoiceHealthState.READY, snapshot[VoiceHealthComponent.ASR].state)
    }

    @Test
    fun registryPreservesFailureUntilARealSuccessOccurs() {
        VoiceRuntimeHealthRegistry.resetForTests()
        VoiceRuntimeHealthRegistry.begin(VoiceRuntimeChannel.LOCAL_WHISPER_ASR, 100L)
        VoiceRuntimeHealthRegistry.failure(
            VoiceRuntimeChannel.LOCAL_WHISPER_ASR,
            " model   failed ",
            200L
        )
        val failed = VoiceRuntimeHealthRegistry.record(
            VoiceRuntimeChannel.LOCAL_WHISPER_ASR
        )
        VoiceRuntimeHealthRegistry.success(VoiceRuntimeChannel.LOCAL_WHISPER_ASR, 300L)
        val recovered = VoiceRuntimeHealthRegistry.record(
            VoiceRuntimeChannel.LOCAL_WHISPER_ASR
        )

        assertEquals(false, failed.active)
        assertEquals("model failed", failed.lastFailureReason)
        assertEquals(300L, recovered.lastSuccessAtMillis)
    }

    private fun evaluate(
        enabled: Boolean = true,
        dependency: VoiceHealthDependency = VoiceHealthDependency(true),
        record: VoiceRuntimeHealthRecord = VoiceRuntimeHealthRecord(),
        nowMillis: Long = 1_000L
    ): VoiceRealtimeHealthSnapshot = VoiceRealtimeHealthPolicy.evaluate(
        probes = listOf(
            VoiceHealthProbe(
                component = VoiceHealthComponent.ASR,
                enabled = enabled,
                provider = "whisper.cpp",
                dependency = dependency,
                runtime = record
            )
        ),
        nowMillis = nowMillis
    )
}
