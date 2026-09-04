package com.galaxyssi.chat.voice.benchmark

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WhisperBenchmarkAudioInstrumentedTest {
    @Test
    fun bundledFixtureIsPrivateVersionedPcm16AndLongEnoughForEveryWindow() {
        val audio = WhisperBenchmarkAudioLoader.load(InstrumentationRegistry.getInstrumentation().targetContext)

        assertTrue(audio.version.startsWith("zh_cn_v1:"))
        assertEquals(WhisperBenchmarkAudio.SAMPLE_RATE_HZ * 3, audio.window(3_000L).size)
        assertEquals(WhisperBenchmarkAudio.SAMPLE_RATE_HZ * 5, audio.window(5_000L).size)
        assertEquals(WhisperBenchmarkAudio.SAMPLE_RATE_HZ * 10, audio.window(10_000L).size)
        assertTrue(audio.expectedTokens.size >= 5)
    }
}
