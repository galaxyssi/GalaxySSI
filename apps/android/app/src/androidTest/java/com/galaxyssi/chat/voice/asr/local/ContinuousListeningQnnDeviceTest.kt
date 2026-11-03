package com.galaxyssi.chat.voice.asr.local

import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.audio.DirectPcmFramePacket
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkAudioLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Authored Chinese PCM and an already-installed QNN model; no download or chat submission. */
class ContinuousListeningQnnDeviceTest {
    @Test fun installedQnnPreservesTheChineseFixtureThroughAnInternalPause() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val installed = LargeTurboQnnModelStore(context.filesDir).inspectActive(LargeTurboQnnModelCatalog.s26Ultra)
        assumeTrue("An installed QNN model is required", installed.state == QnnContextModelState.INSTALLED)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        // Use the installed runtime directly; preparation must never download a model in a test.
        val controller = HighAccuracyLocalAsrController(scope,
            modelDirectoryResolver = { installed.directory },
            engineFactory = { HighAccuracyLocalAsrEngineFactory.create(context) })
        val fixture = WhisperBenchmarkAudioLoader.load(context)
        val split = fixture.pcm16.size / 2
        val audio = fixture.pcm16.copyOfRange(0, split) + ShortArray(11_200) +
            fixture.pcm16.copyOfRange(split, fixture.pcm16.size)
        val buffer = ByteBuffer.allocateDirect(640).order(ByteOrder.LITTLE_ENDIAN)
        try {
            withTimeout(120_000L) {
                assertTrue("The installed QNN runtime must prepare", controller.prepareNow())
                val turn = requireNotNull(controller.startTurnIfReady(AsrConfig(), "large_v3_turbo") {})
                val started = SystemClock.elapsedRealtime()
                var sequence = 0L
                for (offset in audio.indices step 320) {
                    val count = minOf(320, audio.size - offset)
                    buffer.clear()
                    repeat(count) { buffer.putShort(audio[offset + it]) }
                    buffer.flip()
                    assertTrue(turn.offer(DirectPcmFramePacket(sequence++, SystemClock.elapsedRealtimeNanos(),
                        buffer, count, 16_000)))
                    delay(20)
                }
                val result = turn.finish()
                instrumentation.sendStatus(0, Bundle().apply {
                    putString("qnn_fixture_text", result.text)
                    putLong("qnn_fixture_elapsed_ms", SystemClock.elapsedRealtime() - started)
                    putBoolean("qnn_input_complete", result.audioInputComplete)
                    putBoolean("qnn_transcript_complete", result.complete)
                })
                assertTrue("The complete PCM input must survive segmentation", result.audioInputComplete)
                assertTrue("The decoder must finish the utterance", result.complete)
                assertTrue("Most authored keywords must survive", fixture.expectedTokens.count { it in result.text } >= 6)
                assertTrue("The final keyword must not be dropped", "取消" in result.text)
            }
        } finally {
            controller.close()
            scope.cancel()
            audio.fill(0)
            fixture.pcm16.fill(0)
            buffer.clear()
            while (buffer.hasRemaining()) buffer.put(0)
        }
    }
}
