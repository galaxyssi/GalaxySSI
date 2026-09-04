package com.galaxyssi.chat.voice.benchmark

import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WhisperBenchmarkStoreTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun recordRoundTripsWithEvidence() {
        val store = store()
        val record = record(key())

        store.save(record)
        val restored = store.find(record.certification.key)

        assertEquals(record.certification, restored?.certification)
        assertEquals(record.measurements, restored?.measurements)
        assertEquals(listOf(25L, 30L), restored?.abortLatenciesMs)
        assertEquals(listOf(2, 3, 4), restored?.threadCandidates)
    }

    @Test
    fun modelShaAndNativeBuildChangesInvalidateExactCertification() {
        val store = store()
        val original = key()
        store.save(record(original))

        assertNull(store.find(original.copy(modelSha256 = "b".repeat(64))))
        assertNull(store.find(original.copy(nativeBuildFingerprint = "native-b")))
        assertNull(store.find(original.copy(benchmarkAudioVersion = "audio-v2")))
        assertEquals(original, store.find(original)?.certification?.key)
    }

    @Test
    fun malformedStoreFailsClosed() {
        val file = temporaryFolder.newFile("broken.json").apply { writeText("not-json") }
        val store = WhisperBenchmarkStore(file)

        assertNull(store.find(key()))
        store.save(record(key()))
        assertTrue(store.find(key()) != null)
    }

    private fun store() = WhisperBenchmarkStore(temporaryFolder.newFile("benchmark-${System.nanoTime()}.json"))

    private fun key() = WhisperBenchmarkKey(
        manufacturer = "GalaxySSI",
        device = "device-a",
        soc = "soc-a",
        androidApi = 36,
        appVersionCode = 309,
        whisperNativeVersion = "v1",
        nativeBuildFingerprint = "native-a",
        modelProfileId = "tiny",
        modelSha256 = WhisperModelCatalog.require("tiny").sha256,
        benchmarkAudioVersion = "audio-v1"
    )

    private fun record(key: WhisperBenchmarkKey): WhisperBenchmarkRecord {
        val measurement = WhisperBenchmarkMeasurement(
            threadCount = 3,
            loadKind = WhisperBenchmarkLoadKind.COLD,
            audioDurationMs = 5_000L,
            decodeDurationMs = 1_000L,
            realTimeFactor = 0.2,
            loadDurationMs = 100L,
            warmUpDurationMs = 20L,
            peakPssBytes = 128L,
            peakRssBytes = 160L,
            peakNativeAllocatedBytes = 64L,
            cpuTimeMs = 800L,
            energyDeltaNwh = 25L,
            firstPartialLatencyMs = 1_000L,
            finalTailLatencyMs = 0L,
            batteryTemperatureStartCelsius = 30.0,
            batteryTemperatureEndCelsius = 30.5,
            thermalStatusStart = 0,
            thermalStatusEnd = 1,
            transcriptCorrect = true
        )
        return WhisperBenchmarkRecord(
            certification = WhisperCertification(
                key = key,
                level = WhisperCertificationLevel.REALTIME,
                recommendedMode = WhisperExecutionMode.REALTIME_PARTIAL,
                recommendedThreadCount = 3,
                recommendedPartialIntervalMs = 750L,
                warmRtfP50 = 0.2,
                warmRtfP95 = 0.3,
                loadTimeMsP95 = 100L,
                peakPssBytes = 128L,
                maxThermalStatus = 1,
                abortLatencyMsP95 = 30L,
                createdAtEpochMs = 10L,
                failureReason = null
            ),
            measurements = listOf(measurement),
            verificationDurationMs = 15L,
            abortLatenciesMs = listOf(25L, 30L),
            highPerformanceCoreCount = 4,
            threadCandidates = listOf(2, 3, 4)
        )
    }
}
