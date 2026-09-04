package com.galaxyssi.chat.voice.benchmark

import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperCertificationClassifierTest {
    private val profile = WhisperModelCatalog.require("medium_q5_0")

    @Test
    fun measuredRtfSelectsRealtimeFinalAndSecondPassWithoutFamilyHardcoding() {
        assertEquals(WhisperCertificationLevel.REALTIME, classify(0.80).level)
        assertEquals(WhisperExecutionMode.REALTIME_PARTIAL, classify(0.80).mode)
        assertEquals(WhisperCertificationLevel.FINAL, classify(1.50).level)
        assertEquals(WhisperCertificationLevel.SECOND_PASS, classify(2.0).level)
        assertEquals(WhisperCertificationLevel.SECOND_PASS, classify(4.0).level)
    }

    @Test
    fun correctnessAndCancellationFailuresAreUnsupportedWhileThermalRecommendsRemote() {
        val incorrect = classify(0.4, transcriptCorrect = false)
        val hot = classify(0.4, thermalStatus = 3)
        val slowAbort = classify(0.4, abortLatencyMs = 301L)

        listOf(incorrect, slowAbort).forEach { result ->
            assertEquals(WhisperCertificationLevel.UNSUPPORTED, result.level)
            assertEquals(WhisperExecutionMode.REMOTE_NODE, result.mode)
            assertTrue(result.failureReason?.isNotBlank() == true)
        }
        assertEquals(WhisperCertificationLevel.REMOTE_RECOMMENDED, hot.level)
        assertEquals(WhisperExecutionMode.REMOTE_NODE, hot.mode)
    }

    @Test
    fun threadCandidatesAreBoundedAndBestSelectionUsesStableP95() {
        assertEquals(listOf(2, 3, 4, 6, 8), WhisperThreadSearch.candidates(8))
        assertEquals(listOf(1), WhisperThreadSearch.candidates(1))
        val measurements = listOf(
            measurement(2, 0.50), measurement(2, 0.60),
            measurement(4, 0.35), measurement(4, 0.40)
        )
        assertEquals(4, WhisperThreadSearch.selectBest(measurements))
    }

    @Test
    fun allModelFamiliesUseMeasuredThresholdsInsteadOfCatalogDefaults() {
        val cases = listOf(
            Triple("tiny", 0.4, WhisperCertificationLevel.REALTIME),
            Triple("base", 0.9, WhisperCertificationLevel.FINAL),
            Triple("small", 1.3, WhisperCertificationLevel.FINAL),
            Triple("medium", 2.2, WhisperCertificationLevel.SECOND_PASS),
            Triple("large", 3.5, WhisperCertificationLevel.SECOND_PASS),
            Triple("large_v3_turbo_q5_0", 0.7, WhisperCertificationLevel.REALTIME)
        )

        cases.forEach { (profileId, rtf, expected) ->
            val result = WhisperCertificationClassifier.classify(
                profile = WhisperModelCatalog.require(profileId),
                rtfP95 = rtf,
                transcriptCorrect = true,
                maxThermalStatus = 0,
                abortLatencyMsP95 = 50L
            )
            assertEquals(profileId, expected, result.level)
        }
    }

    private fun classify(
        rtf: Double,
        transcriptCorrect: Boolean = true,
        thermalStatus: Int = 0,
        abortLatencyMs: Long = 50L
    ) = WhisperCertificationClassifier.classify(
        profile,
        rtf,
        transcriptCorrect,
        thermalStatus,
        abortLatencyMs
    )

    private fun measurement(threads: Int, rtf: Double) = WhisperBenchmarkMeasurement(
        threadCount = threads,
        loadKind = WhisperBenchmarkLoadKind.HOT,
        audioDurationMs = 3_000L,
        decodeDurationMs = (3_000L * rtf).toLong(),
        realTimeFactor = rtf,
        loadDurationMs = 100L,
        warmUpDurationMs = 10L,
        peakPssBytes = 1L,
        peakRssBytes = 1L,
        peakNativeAllocatedBytes = 1L,
        cpuTimeMs = 1L,
        energyDeltaNwh = null,
        firstPartialLatencyMs = 1L,
        finalTailLatencyMs = 0L,
        batteryTemperatureStartCelsius = null,
        batteryTemperatureEndCelsius = null,
        thermalStatusStart = 0,
        thermalStatusEnd = 0,
        transcriptCorrect = true
    )
}
