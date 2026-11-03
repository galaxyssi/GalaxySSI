package com.galaxyssi.chat

import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Opt-in real service test. Speaks fixed text only; never changes voice settings or uses chat text. */
class MicrosoftEdgeTtsLiveDeviceTest {
    @Test
    fun xiaoxiaoSynthesizesAndPlaysWithV2() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("edge_tts_live") == "true")
        val tts = MicrosoftEdgeTts(InstrumentationRegistry.getInstrumentation().targetContext)
        try {
            play(tts, "\u4f60\u597d\uff0c\u8fd9\u662f\u6653\u6653\u8bed\u97f3\u6d4b\u8bd5\u3002", "")
        } finally {
            tts.shutdown()
        }
    }

    @Test
    fun prefetchedParagraphsUseTheSameVoiceAndCompleteInOrder() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("edge_tts_live") == "true")
        val tts = MicrosoftEdgeTts(InstrumentationRegistry.getInstrumentation().targetContext)
        val texts = listOf("\u8fd9\u662f\u7b2c\u4e00\u6bb5\u8bed\u97f3\u3002", "\u8fd9\u662f\u9884\u53d6\u7684\u7b2c\u4e8c\u6bb5\u3002")
        try {
            texts.forEachIndexed { index, text ->
                tts.prefetch("edge-v2-live", "edge-v2-$index", text, MicrosoftTtsVoiceCatalog.XIAOXIAO)
            }
            texts.forEachIndexed { index, text -> play(tts, text, "edge-v2-$index") }
        } finally {
            tts.shutdown()
        }
    }

    private fun play(tts: MicrosoftEdgeTts, text: String, key: String) {
        val done = CountDownLatch(1)
        val started = AtomicBoolean(false)
        val success = AtomicBoolean(false)
        val error = AtomicReference<String?>()
        val startMs = SystemClock.elapsedRealtime()
        tts.speak(text, MicrosoftTtsVoiceCatalog.XIAOXIAO, prefetchKey = key,
            onPlaybackStarted = {
                started.set(true)
                report("playback_started key=$key voice=${MicrosoftTtsVoiceCatalog.XIAOXIAO} elapsed_ms=${SystemClock.elapsedRealtime() - startMs}")
            }) { ok, reason ->
            success.set(ok)
            error.set(reason)
            done.countDown()
        }
        assertTrue("TTS completion timed out", done.await(45, TimeUnit.SECONDS))
        assertTrue("TTS failed: ${error.get()}", success.get())
        assertTrue("Audio never entered playback", started.get())
        report("playback_completed key=$key elapsed_ms=${SystemClock.elapsedRealtime() - startMs}")
    }

    private fun report(message: String) {
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply { putString("stream", "$message\n") })
    }
}
