package com.galaxyssi.chat.voice.audio

import android.Manifest
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidPcmRecorderInstrumentedTest {
    @Test
    fun capturesPcm16AndCancelsPromptly() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.RECORD_AUDIO)
        val recorder = AndroidPcmRecorder(context)
        val frames = recorder.start(PcmCaptureConfig(maxDurationMs = 5_000L))
        val frame = withTimeout(3_000L) { frames.first() }

        try {
            assertEquals(320, frame.samples.size)
            assertTrue(frame.validSamples in 1..320)
            assertEquals(PcmRecorderPhase.RECORDING, recorder.currentState().phase)
        } finally {
            frame.close()
        }
        val startedAt = SystemClock.elapsedRealtime()
        recorder.stop(PcmStopReason.USER_CANCEL)

        assertTrue(SystemClock.elapsedRealtime() - startedAt < 1_000L)
        assertEquals(PcmStopReason.USER_CANCEL, recorder.currentState().stopReason)
        assertEquals(PcmRecorderPhase.STOPPED, recorder.currentState().phase)
    }
}
