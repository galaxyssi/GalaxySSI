package com.galaxyssi.chat.voice.benchmark

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.galaxyssi.chat.WhisperModelManager
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WhisperBenchmarkDeviceInstrumentedTest {
    @Test
    fun bundledTinyCompletesDeviceCertificationWithPrivateEvidence() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val profile = WhisperModelCatalog.require("tiny")
        assertTrue(WhisperModelManager.ensureVerifiedFile(context, profile).isFile)

        val record = WhisperBenchmarkManager.benchmark(context, profile, force = true)
        val persisted = WhisperBenchmarkManager.current(context, profile)

        assertEquals(profile.id, record.certification.key.modelProfileId)
        assertEquals(profile.sha256, record.certification.key.modelSha256)
        assertEquals(record.certification, persisted?.certification)
        assertTrue(record.measurements.size >= 7)
        assertTrue(record.measurements.any { it.loadKind == WhisperBenchmarkLoadKind.COLD })
        assertTrue(record.measurements.any { it.loadKind == WhisperBenchmarkLoadKind.HOT })
        assertTrue(record.measurements.all { it.audioDurationMs in 3_000L..10_000L })
        assertTrue(record.abortLatenciesMs.isNotEmpty())
        val persistedMeasurements = record.toJson().getJSONArray("measurements")
        repeat(persistedMeasurements.length()) { index ->
            assertTrue(!persistedMeasurements.getJSONObject(index).has("transcript"))
        }
    }
}
