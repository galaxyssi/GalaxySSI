package com.galaxyssi.chat.voice.reliability

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceRolloutPolicyTest {
    @Test
    fun `developer stage requires a debuggable build`() {
        assertFalse(decide(config(stage = VoiceRolloutStage.DEVELOPER)).enabled)
        assertTrue(decide(config(stage = VoiceRolloutStage.DEVELOPER, debuggable = true)).enabled)
    }

    @Test
    fun `opt in beta honors explicit user enable`() {
        val decision = decide(config(
            stage = VoiceRolloutStage.OPT_IN_BETA,
            requestedEnabled = true,
            betaOptIn = true
        ))

        assertTrue(decision.enabled)
    }

    @Test
    fun `privacy and diagnostics remain hard gates`() {
        val evidence = safeEvidence().copy(privacyReviewed = false, diagnosticsAvailable = false)
        val decision = decide(config(
            stage = VoiceRolloutStage.OPT_IN_BETA,
            requestedEnabled = true,
            betaOptIn = true
        ), evidence)

        assertFalse(decision.enabled)
        assertTrue("privacy_review_required" in decision.reasonCodes)
        assertTrue("diagnostics_required" in decision.reasonCodes)
    }

    @Test
    fun `local realtime needs device certification`() {
        val decision = decide(
            config(
                feature = VoicePipelineFeature.LOCAL_WHISPER_REALTIME,
                stage = VoiceRolloutStage.DEVELOPER,
                debuggable = true
            ),
            safeEvidence().copy(deviceCertified = false)
        )

        assertFalse(decision.enabled)
        assertEquals(VoiceRollbackLevel.FINAL_ONLY, decision.rollbackLevel)
    }

    @Test
    fun `stable default rejects missing samples and p95 evidence`() {
        val decision = decide(
            config(stage = VoiceRolloutStage.DEFAULT_WITH_FALLBACK),
            safeEvidence().copy(sampleCount = 20, newP95Ms = null, legacyP95Ms = null)
        )

        assertFalse(decision.enabled)
        assertTrue("insufficient_samples" in decision.reasonCodes)
        assertTrue("p95_evidence_missing" in decision.reasonCodes)
    }

    @Test
    fun `stable default enables only after quality gates pass`() {
        val decision = decide(
            config(stage = VoiceRolloutStage.DEFAULT_WITH_FALLBACK),
            safeEvidence().copy(
                sampleCount = 500,
                stableReleaseCount = 3,
                newP95Ms = 700,
                legacyP95Ms = 1_000,
                fallbackSuccessRate = 0.995
            )
        )

        assertTrue(decision.enabled)
        assertEquals(VoiceRollbackLevel.NONE, decision.rollbackLevel)
    }

    @Test
    fun `open circuit forces single feature rollback`() {
        val decision = decide(
            config(stage = VoiceRolloutStage.DEVELOPER, debuggable = true),
            safeEvidence().copy(circuitState = VoiceCircuitState.OPEN)
        )

        assertFalse(decision.enabled)
        assertEquals(VoiceRollbackLevel.DISABLE_SINGLE_OPTIMIZATION, decision.rollbackLevel)
    }

    @Test
    fun `cohort assignment is stable and feature specific`() {
        val first = VoiceCohortAssigner.bucket("device-17", VoicePipelineFeature.ONLINE_REALTIME_ASR)
        val repeat = VoiceCohortAssigner.bucket("device-17", VoicePipelineFeature.ONLINE_REALTIME_ASR)
        val other = VoiceCohortAssigner.bucket("device-17", VoicePipelineFeature.PROGRESSIVE_TTS)

        assertEquals(first, repeat)
        assertTrue(first in 0..99)
        assertTrue(other in 0..99)
    }

    private fun decide(
        config: VoiceRolloutConfig,
        evidence: VoiceRolloutEvidence = safeEvidence()
    ) = VoiceRolloutPolicy.decide(config, evidence, "stable-device")

    private fun config(
        feature: VoicePipelineFeature = VoicePipelineFeature.ONLINE_REALTIME_ASR,
        stage: VoiceRolloutStage,
        requestedEnabled: Boolean = false,
        debuggable: Boolean = false,
        betaOptIn: Boolean = false
    ) = VoiceRolloutConfig(
        feature = feature,
        stage = stage,
        cohortPercent = 100,
        requestedEnabled = requestedEnabled,
        debuggable = debuggable,
        betaOptIn = betaOptIn
    )

    private fun safeEvidence() = VoiceRolloutEvidence(
        sampleCount = 500,
        stableReleaseCount = 3,
        newP95Ms = 700,
        legacyP95Ms = 1_000,
        fallbackSuccessRate = 1.0,
        privacyReviewed = true,
        securityReviewed = true,
        diagnosticsAvailable = true,
        supportDocumentationAvailable = true,
        deviceCertified = true
    )
}
