package com.galaxyssi.chat.voice.benchmark

import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperRuntimePolicyEngineTest {
    @Test
    fun automaticUsesOnlyRealtimeCertifiedModels() {
        val tiny = WhisperModelCatalog.require("tiny")
        val base = WhisperModelCatalog.require("base")
        val decision = decide(
            candidates = listOf(
                candidate(tiny, WhisperCertificationLevel.FINAL, WhisperExecutionMode.FINAL_ONLY, 0.9),
                candidate(base, WhisperCertificationLevel.REALTIME, WhisperExecutionMode.REALTIME_PARTIAL, 0.5)
            )
        )

        assertEquals(WhisperProviderChoice.LOCAL, decision.provider)
        assertEquals(base.id, decision.fastProfileId)
        assertEquals(WhisperExecutionMode.REALTIME_PARTIAL, decision.fastMode)
    }

    @Test
    fun automaticDoesNotPromoteFinalOrUntestedModelsToRealtime() {
        val medium = WhisperModelCatalog.require("medium_q5_0")
        val decision = decide(
            candidates = listOf(
                candidate(medium, WhisperCertificationLevel.FINAL, WhisperExecutionMode.FINAL_ONLY, 1.0),
                WhisperRuntimeCandidate(WhisperModelCatalog.require("tiny"), installed = true, certification = null)
            )
        )

        assertEquals(WhisperProviderChoice.REMOTE, decision.provider)
        assertNull(decision.fastProfileId)
        assertFalse(decision.runSecondPass)
    }

    @Test
    fun automaticUsesInstalledModelInFinalModeWhenRemoteIsUnavailable() {
        val tiny = WhisperModelCatalog.require("tiny")
        val decision = decide(
            candidates = listOf(
                WhisperRuntimeCandidate(tiny, installed = true, certification = null)
            ),
            environment = environment(remoteAllowed = false)
        )

        assertEquals(WhisperProviderChoice.LOCAL, decision.provider)
        assertEquals(tiny.id, decision.fastProfileId)
        assertEquals(WhisperExecutionMode.FINAL_ONLY, decision.fastMode)
        assertEquals(2, decision.threadCount)
        assertFalse(decision.runSecondPass)
    }

    @Test
    fun sameModelCanReceiveDifferentModesOnDifferentDeviceCertifications() {
        val profile = WhisperModelCatalog.require("small_q5_1")
        val fastDevice = decide(
            candidates = listOf(candidate(profile, WhisperCertificationLevel.REALTIME, WhisperExecutionMode.REALTIME_PARTIAL, 0.55))
        )
        val slowDevice = decide(
            candidates = listOf(candidate(profile, WhisperCertificationLevel.SECOND_PASS, WhisperExecutionMode.SECOND_PASS, 2.2))
        )

        assertEquals(WhisperProviderChoice.LOCAL, fastDevice.provider)
        assertEquals(WhisperExecutionMode.REALTIME_PARTIAL, fastDevice.fastMode)
        assertEquals(WhisperProviderChoice.REMOTE, slowDevice.provider)
    }

    @Test
    fun mediumCanBeRealtimeOnlyWhenMeasuredCertificationSaysSo() {
        val medium = WhisperModelCatalog.require("medium_q5_0")
        val certified = decide(
            candidates = listOf(candidate(medium, WhisperCertificationLevel.REALTIME, WhisperExecutionMode.REALTIME_PARTIAL, 0.6))
        )
        val backgroundOnly = decide(
            candidates = listOf(candidate(medium, WhisperCertificationLevel.SECOND_PASS, WhisperExecutionMode.SECOND_PASS, 1.8))
        )

        assertEquals(medium.id, certified.fastProfileId)
        assertEquals(WhisperProviderChoice.REMOTE, backgroundOnly.provider)
    }

    @Test
    fun lowMemoryAndSevereThermalPressureRecommendRemote() {
        val large = WhisperModelCatalog.require("large_v3_q5_0")
        val certified = candidate(large, WhisperCertificationLevel.REALTIME, WhisperExecutionMode.REALTIME_PARTIAL, 0.6)
        val lowMemory = decide(
            candidates = listOf(certified),
            environment = environment(availableMemoryBytes = 128L * MIB)
        )
        val hot = decide(
            candidates = listOf(certified),
            environment = environment(thermalStatus = 3)
        )

        assertEquals(WhisperProviderChoice.REMOTE, lowMemory.provider)
        assertTrue(lowMemory.reasons.any { "memory" in it.lowercase() })
        assertEquals(WhisperProviderChoice.REMOTE, hot.provider)
        assertTrue(hot.reasons.any { "thermal" in it.lowercase() })
    }

    @Test
    fun thermalAndQueuePressureReduceCertifiedRealtimeWork() {
        val tiny = WhisperModelCatalog.require("tiny")
        val decision = decide(
            candidates = listOf(candidate(tiny, WhisperCertificationLevel.REALTIME, WhisperExecutionMode.REALTIME_PARTIAL, 0.4)),
            environment = environment(thermalStatus = 2, decodeQueueDepth = 2)
        )

        assertEquals(WhisperProviderChoice.LOCAL, decision.provider)
        assertEquals(2, decision.threadCount)
        assertTrue(requireNotNull(decision.partialIntervalMs) >= 3_000L)
        assertTrue(decision.reasons.any { "backlog" in it.lowercase() })
    }

    @Test
    fun manualModeCanRetryRemoteRecommendedModelButNeverUnsupportedNativeModel() {
        val tiny = WhisperModelCatalog.require("tiny")
        val retry = WhisperRuntimePolicyEngine.decide(
            WhisperRuntimePolicyInput(
                userMode = WhisperUserVoiceMode.MANUAL,
                selectedProfileId = tiny.id,
                candidates = listOf(candidate(
                    tiny,
                    WhisperCertificationLevel.REMOTE_RECOMMENDED,
                    WhisperExecutionMode.REMOTE_NODE,
                    2.0
                )),
                environment = environment()
            )
        )
        val unsupported = WhisperRuntimePolicyEngine.decide(
            WhisperRuntimePolicyInput(
                userMode = WhisperUserVoiceMode.MANUAL,
                selectedProfileId = tiny.id,
                candidates = listOf(candidate(
                    tiny,
                    WhisperCertificationLevel.UNSUPPORTED,
                    WhisperExecutionMode.REMOTE_NODE,
                    2.0
                )),
                environment = environment()
            )
        )

        assertEquals(WhisperProviderChoice.LOCAL, retry.provider)
        assertEquals(WhisperExecutionMode.FINAL_ONLY, retry.fastMode)
        assertEquals(WhisperProviderChoice.REMOTE, unsupported.provider)
        assertNull(unsupported.fastProfileId)
    }

    @Test
    fun memoryGateUsesCertifiedIncrementAboveCurrentProcessPss() {
        val tiny = WhisperModelCatalog.require("tiny")
        val measured = candidate(
            tiny,
            WhisperCertificationLevel.REALTIME,
            WhisperExecutionMode.REALTIME_PARTIAL,
            0.4
        ).let { candidate ->
            candidate.copy(certification = candidate.certification?.copy(peakPssBytes = 800L * MIB))
        }

        val decision = decide(
            candidates = listOf(measured),
            environment = environment(
                availableMemoryBytes = 500L * MIB,
                currentPssBytes = 600L * MIB
            )
        )

        assertEquals(WhisperProviderChoice.LOCAL, decision.provider)
    }

    @Test
    fun fastModeStillSchedulesCertifiedAccuracyPassForHighRiskSpeech() {
        val tiny = WhisperModelCatalog.require("tiny")
        val medium = WhisperModelCatalog.require("medium_q5_0")
        val decision = WhisperRuntimePolicyEngine.decide(
            WhisperRuntimePolicyInput(
                userMode = WhisperUserVoiceMode.FAST,
                selectedProfileId = tiny.id,
                candidates = listOf(
                    candidate(tiny, WhisperCertificationLevel.REALTIME, WhisperExecutionMode.REALTIME_PARTIAL, 0.4),
                    candidate(medium, WhisperCertificationLevel.SECOND_PASS, WhisperExecutionMode.SECOND_PASS, 1.8)
                ),
                environment = environment(highRiskTask = true)
            )
        )

        assertEquals(tiny.id, decision.fastProfileId)
        assertEquals(medium.id, decision.accurateProfileId)
        assertTrue(decision.runSecondPass)
    }

    @Test
    fun privacyAndManualModesKeepHighRiskAccuracyPassLocal() {
        val tiny = WhisperModelCatalog.require("tiny")
        val medium = WhisperModelCatalog.require("medium_q5_0")
        listOf(WhisperUserVoiceMode.PRIVACY, WhisperUserVoiceMode.MANUAL).forEach { mode ->
            val decision = WhisperRuntimePolicyEngine.decide(
                WhisperRuntimePolicyInput(
                    userMode = mode,
                    selectedProfileId = tiny.id,
                    candidates = listOf(
                        candidate(tiny, WhisperCertificationLevel.REALTIME, WhisperExecutionMode.REALTIME_PARTIAL, 0.4),
                        candidate(medium, WhisperCertificationLevel.SECOND_PASS, WhisperExecutionMode.SECOND_PASS, 1.8)
                    ),
                    environment = environment(highRiskTask = true)
                )
            )

            assertEquals(WhisperProviderChoice.LOCAL, decision.provider)
            assertEquals(medium.id, decision.accurateProfileId)
            assertTrue(decision.runSecondPass)
        }
    }

    @Test
    fun powerSaverKeepsTheSelectedLocalModelButDisablesPartialAndSecondPassWork() {
        val tiny = WhisperModelCatalog.require("tiny")
        val medium = WhisperModelCatalog.require("medium_q5_0")
        val decision = WhisperRuntimePolicyEngine.decide(
            WhisperRuntimePolicyInput(
                userMode = WhisperUserVoiceMode.POWER_SAVER,
                selectedProfileId = medium.id,
                candidates = listOf(
                    candidate(tiny, WhisperCertificationLevel.REALTIME, WhisperExecutionMode.REALTIME_PARTIAL, 0.4),
                    candidate(medium, WhisperCertificationLevel.FINAL, WhisperExecutionMode.FINAL_ONLY, 1.4)
                ),
                environment = environment(highRiskTask = true)
            )
        )

        assertEquals(WhisperProviderChoice.LOCAL, decision.provider)
        assertEquals(medium.id, decision.fastProfileId)
        assertEquals(WhisperExecutionMode.FINAL_ONLY, decision.fastMode)
        assertFalse(decision.runSecondPass)
        assertNull(decision.partialIntervalMs)
    }

    private fun decide(
        candidates: List<WhisperRuntimeCandidate>,
        environment: WhisperRuntimeEnvironment = environment()
    ): WhisperRuntimeDecision = WhisperRuntimePolicyEngine.decide(
        WhisperRuntimePolicyInput(
            userMode = WhisperUserVoiceMode.AUTOMATIC,
            selectedProfileId = candidates.firstOrNull()?.profile?.id,
            candidates = candidates,
            environment = environment
        )
    )

    private fun candidate(
        profile: WhisperModelProfile,
        level: WhisperCertificationLevel,
        mode: WhisperExecutionMode,
        rtfP95: Double
    ) = WhisperRuntimeCandidate(
        profile = profile,
        installed = true,
        certification = certification(profile, level, mode, rtfP95)
    )

    private fun certification(
        profile: WhisperModelProfile,
        level: WhisperCertificationLevel,
        mode: WhisperExecutionMode,
        rtfP95: Double
    ) = WhisperCertification(
        key = key(profile),
        level = level,
        recommendedMode = mode,
        recommendedThreadCount = 4,
        recommendedPartialIntervalMs = if (mode == WhisperExecutionMode.REALTIME_PARTIAL) 750L else 0L,
        warmRtfP50 = rtfP95 * 0.8,
        warmRtfP95 = rtfP95,
        loadTimeMsP95 = 100L,
        peakPssBytes = 96L * MIB,
        maxThermalStatus = 0,
        abortLatencyMsP95 = 50L,
        createdAtEpochMs = 1L,
        failureReason = null
    )

    private fun key(profile: WhisperModelProfile) = WhisperBenchmarkKey(
        manufacturer = "GalaxySSI",
        device = "test-device",
        soc = "test-soc",
        androidApi = 36,
        appVersionCode = 310,
        whisperNativeVersion = "v1",
        nativeBuildFingerprint = "native-a",
        modelProfileId = profile.id,
        modelSha256 = profile.sha256,
        benchmarkAudioVersion = "audio-v1"
    )

    private fun environment(
        availableMemoryBytes: Long = 8L * 1_024L * MIB,
        currentPssBytes: Long = 100L * MIB,
        thermalStatus: Int = 0,
        decodeQueueDepth: Int = 0,
        highRiskTask: Boolean = false,
        remoteAllowed: Boolean = true
    ) = WhisperRuntimeEnvironment(
        network = WhisperNetworkState.UNMETERED,
        availableMemoryBytes = availableMemoryBytes,
        currentPssBytes = currentPssBytes,
        thermalStatus = thermalStatus,
        batteryPercent = 80,
        charging = true,
        foreground = true,
        recentRealTimeFactor = null,
        decodeQueueDepth = decodeQueueDepth,
        utteranceDurationMs = 5_000L,
        highRiskTask = highRiskTask,
        remoteAllowed = remoteAllowed
    )

    private companion object {
        const val MIB = 1_048_576L
    }
}
