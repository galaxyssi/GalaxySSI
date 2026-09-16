package com.galaxyssi.watch

import android.speech.*
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.Assume.assumeTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class WatchWakeTest {
    @Test fun offlineModelRecognizesWakeAndRejectsOtherSpeech() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("wake_audio_diagnostic") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        org.vosk.Model(org.vosk.android.StorageService.sync(context, "model-en-us", "wake-model")).use { model ->
            fun detect(name: String): Boolean {
                org.vosk.Recognizer(model, 16000f, "[\"hello hello\", \"[unk]\"]").use { recognizer ->
                    recognizer.setWords(true)
                    val data = java.io.File(context.getExternalFilesDir(null), name).readBytes()
                    var hit = false
                    var offset = 0
                    while (offset < data.size) {
                        val end = minOf(offset + 3200, data.size)
                        val part = data.copyOfRange(offset, end)
                        if (recognizer.acceptWaveForm(part, part.size)) hit = hit || WatchWakePolicy.confidentResult(recognizer.result)
                        offset = end
                    }
                    hit = hit || WatchWakePolicy.confidentResult(recognizer.finalResult)
                    data.fill(0)
                    return hit
                }
            }
            org.junit.Assert.assertTrue("Expected Hello Hello detection", detect("wake-hello-hello.pcm"))
            org.junit.Assert.assertFalse("Other speech must not wake", detect("wake-negative.pcm"))
        }
    }

    @Test fun microphoneIsReleasedBeforeHandoffAndClosedOnStop() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("wake_audio_diagnostic") == "true")
        val inst = InstrumentationRegistry.getInstrumentation()
        val activity = inst.startActivitySync(android.content.Intent(inst.targetContext, MainActivity::class.java)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val ready = CountDownLatch(1)
        val stopped = CountDownLatch(1)
        var state = WatchForegroundWake.State.OFF
        var hits = 0
        lateinit var wake: WatchForegroundWake
        try {
            inst.runOnMainSync {
                wake = WatchForegroundWake(activity, { state = it; if (it in setOf(WatchForegroundWake.State.LISTENING, WatchForegroundWake.State.FAILED)) ready.countDown() }, { hits++ })
                wake.setEnabled(true)
            }
            org.junit.Assert.assertTrue(ready.await(35, TimeUnit.SECONDS))
            org.junit.Assert.assertEquals(WatchForegroundWake.State.LISTENING, state)
            inst.runOnMainSync { wake.stopThen { stopped.countDown() } }
            org.junit.Assert.assertTrue(stopped.await(5, TimeUnit.SECONDS))
            inst.runOnMainSync {
                org.junit.Assert.assertEquals(WatchForegroundWake.State.PAUSED, wake.state)
                org.junit.Assert.assertEquals(0, hits)
                val recorder = WatchForegroundWake::class.java.getDeclaredField("recorder").apply { isAccessible = true }.get(wake)
                org.junit.Assert.assertNull("Capture must be released before handoff", recorder)
            }
        } finally { inst.runOnMainSync { wake.shutdown(); activity.finish() } }
    }

    @Test fun foregroundWakeHandsOffToSpeechAndStopsInBackground() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("wake_handoff_diagnostic") == "true")
        val inst = InstrumentationRegistry.getInstrumentation()
        val repo = (inst.targetContext.applicationContext as WatchApplication).repository
        repo.store.tasks()
        val activity = inst.startActivitySync(android.content.Intent(inst.targetContext, MainActivity::class.java)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val monitor = inst.addMonitor(android.content.IntentFilter(RecognizerIntent.ACTION_RECOGNIZE_SPEECH),
            android.app.Instrumentation.ActivityResult(android.app.Activity.RESULT_CANCELED, null), true)
        lateinit var wake: WatchForegroundWake
        fun awaitState(expected: WatchForegroundWake.State) {
            val deadline = android.os.SystemClock.elapsedRealtime() + 35000
            var value = WatchForegroundWake.State.OFF
            while (android.os.SystemClock.elapsedRealtime() < deadline) {
                inst.runOnMainSync { value = wake.state }
                if (value == expected) return
                Thread.sleep(100)
            }
            org.junit.Assert.assertEquals(expected, value)
        }
        try {
            inst.waitForIdleSync()
            inst.runOnMainSync {
                MainActivity::class.java.getDeclaredMethod("setWakePreference", Boolean::class.javaPrimitiveType)
                    .apply { isAccessible = true }.invoke(activity, true)
                wake = MainActivity::class.java.getDeclaredField("wake").apply { isAccessible = true }.get(activity) as WatchForegroundWake
            }
            awaitState(WatchForegroundWake.State.LISTENING)
            inst.runOnMainSync {
                val root = activity.window.decorView
                val image = android.graphics.Bitmap.createBitmap(root.width, root.height, android.graphics.Bitmap.Config.ARGB_8888)
                root.draw(android.graphics.Canvas(image))
                java.io.File(activity.getExternalFilesDir(null), "wake-listening.png").outputStream().use { image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                image.recycle()
                @Suppress("UNCHECKED_CAST")
                val callback = WatchForegroundWake::class.java.getDeclaredField("onWake").apply { isAccessible = true }.get(wake) as () -> Unit
                callback()
            }
            val deadline = android.os.SystemClock.elapsedRealtime() + 10000
            while (monitor.hits == 0 && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
            org.junit.Assert.assertEquals("Wake should open speech input exactly once", 1, monitor.hits)
            inst.runOnMainSync {
                org.junit.Assert.assertNull(WatchForegroundWake::class.java.getDeclaredField("recorder").apply { isAccessible = true }.get(wake))
                activity.moveTaskToBack(true)
            }
            awaitState(WatchForegroundWake.State.PAUSED)
            Thread.sleep(500)
            inst.runOnMainSync {
                org.junit.Assert.assertNull("Background must release microphone", WatchForegroundWake::class.java.getDeclaredField("recorder").apply { isAccessible = true }.get(wake))
            }
        } finally {
            inst.removeMonitor(monitor)
            inst.runOnMainSync { activity.finish() }
        }
    }

    @Test fun inspectLocalRecognition() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("wake_diagnostic") == "true")
        val inst = InstrumentationRegistry.getInstrumentation()
        val done = CountDownLatch(1)
        var recognizer: SpeechRecognizer? = null
        inst.runOnMainSync {
            val available = SpeechRecognizer.isOnDeviceRecognitionAvailable(inst.targetContext)
            println("WATCH_WAKE on_device=$available")
            if (!available) done.countDown() else {
                recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(inst.targetContext)
                recognizer!!.checkRecognitionSupport(android.content.Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM),
                    inst.targetContext.mainExecutor, object : RecognitionSupportCallback {
                        override fun onSupportResult(support: RecognitionSupport) {
                            println("WATCH_WAKE installed=${support.installedOnDeviceLanguages} downloadable=${support.supportedOnDeviceLanguages}")
                            done.countDown()
                        }
                        override fun onError(error: Int) { println("WATCH_WAKE support_error=$error"); done.countDown() }
                    })
            }
        }
        try { org.junit.Assert.assertTrue(done.await(20, TimeUnit.SECONDS)) }
        finally { inst.runOnMainSync { recognizer?.destroy() } }
    }
}
