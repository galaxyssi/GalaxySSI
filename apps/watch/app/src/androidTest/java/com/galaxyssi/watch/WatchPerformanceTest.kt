package com.galaxyssi.watch

import android.content.Intent
import android.speech.RecognizerIntent
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.Assume.assumeTrue

class WatchPerformanceTest {
    @Test fun unchangedSessionsReuseTheirView() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val repo = (instrumentation.targetContext.applicationContext as WatchApplication).repository
        repo.store.tasks()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        repo.awaitUiStorage()
        val navigate = MainActivity::class.java.getDeclaredMethod("navigate", String::class.java).apply { isAccessible = true }
        val back = MainActivity::class.java.getDeclaredMethod("back").apply { isAccessible = true }
        val frame = MainActivity::class.java.getDeclaredField("sessionsFrame").apply { isAccessible = true }
        try {
            instrumentation.runOnMainSync {
                navigate.invoke(activity, "sessions")
                val first = frame.get(activity)
                org.junit.Assert.assertNotNull(first)
                back.invoke(activity)
                navigate.invoke(activity, "sessions")
                org.junit.Assert.assertSame(first, frame.get(activity))
                MainActivity::class.java.getDeclaredField("sessionQuery").apply { isAccessible = true }.set(activity, "no-match-fixture")
                MainActivity::class.java.getDeclaredMethod("render", Boolean::class.javaPrimitiveType).apply { isAccessible = true }.invoke(activity, false)
                org.junit.Assert.assertNotSame(first, frame.get(activity))
            }
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }

    @Test fun speechAutomaticallySendsWithoutWaitingForTransport() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("speech_send_diagnostic") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val repo = (instrumentation.targetContext.applicationContext as WatchApplication).repository
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        val oldIds = repo.store.tasks().map { it.id }.toSet()
        val release = java.util.concurrent.CountDownLatch(1)
        val blocked = java.util.concurrent.CountDownLatch(1)
        val transport = WatchRepository::class.java.getDeclaredField("worker").apply { isAccessible = true }
            .get(repo) as java.util.concurrent.ExecutorService
        transport.execute { blocked.countDown(); release.await(15, java.util.concurrent.TimeUnit.SECONDS) }
        org.junit.Assert.assertTrue(blocked.await(15, java.util.concurrent.TimeUnit.SECONDS))
        val start = SystemClock.elapsedRealtime()
        try {
            instrumentation.runOnMainSync {
                MainActivity::class.java.getDeclaredMethod("onActivityResult", Int::class.javaPrimitiveType,
                    Int::class.javaPrimitiveType, Intent::class.java).apply { isAccessible = true }
                    .invoke(activity, 31, android.app.Activity.RESULT_OK, Intent().putStringArrayListExtra(
                        RecognizerIntent.EXTRA_RESULTS, arrayListOf("Reply with just OK.")))
            }
            val deadline = start + 10_000
            while (repo.store.cachedTasks().none { it.id !in oldIds } && SystemClock.elapsedRealtime() < deadline) Thread.sleep(20)
            val task = repo.store.cachedTasks().firstOrNull { it.id !in oldIds }
            org.junit.Assert.assertNotNull("Speech should send while transport is blocked", task)
            println("WATCH_PERF speech_auto_send_ms=${SystemClock.elapsedRealtime() - start}")
            release.countDown()
            val replyDeadline = SystemClock.elapsedRealtime() + 190_000
            while (repo.store.cachedTask(requireNotNull(task).id)?.state?.terminal != true && SystemClock.elapsedRealtime() < replyDeadline) Thread.sleep(100)
            org.junit.Assert.assertEquals(TaskState.COMPLETED, repo.store.cachedTask(requireNotNull(task).id)?.state)
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                org.junit.Assert.assertEquals("home", MainActivity::class.java.getDeclaredField("page").apply { isAccessible = true }.get(activity))
            }
        } finally { release.countDown() }
    }

    @Test fun navigationAndSpeechReturnLatency() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("performance_diagnostic") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        val navigate = MainActivity::class.java.getDeclaredMethod("navigate", String::class.java).apply { isAccessible = true }
        val back = MainActivity::class.java.getDeclaredMethod("back").apply { isAccessible = true }
        val result = MainActivity::class.java.getDeclaredMethod("onActivityResult", Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType, Intent::class.java).apply { isAccessible = true }
        val repo = (activity.application as WatchApplication).repository
        val homeField = MainActivity::class.java.getDeclaredField("conversationView").apply { isAccessible = true }
        val originalHome = homeField.get(activity)
        try {
            repeat(3) { iteration ->
                for (page in listOf("home-menu", "sessions")) {
                    if (InstrumentationRegistry.getArguments().getString("expire_preferences") == "true") {
                        val cache = Class.forName("com.galaxyssi.chat.AgentEncryptedPreferenceCache")
                        cache.getDeclaredMethod("clearAll").apply { isAccessible = true }
                            .invoke(cache.getDeclaredField("INSTANCE").apply { isAccessible = true }.get(null))
                    }
                    val drawn = java.util.concurrent.CountDownLatch(1)
                    instrumentation.runOnMainSync {
                        val start = SystemClock.elapsedRealtime()
                        navigate.invoke(activity, page)
                        println("WATCH_PERF route=$page iteration=$iteration enter_handler_ms=${SystemClock.elapsedRealtime() - start}")
                        val root = activity.window.decorView
                        root.viewTreeObserver.addOnPreDrawListener(object : android.view.ViewTreeObserver.OnPreDrawListener {
                            override fun onPreDraw(): Boolean {
                                root.viewTreeObserver.removeOnPreDrawListener(this)
                                println("WATCH_PERF route=$page iteration=$iteration enter_predraw_ms=${SystemClock.elapsedRealtime() - start}")
                                drawn.countDown()
                                return true
                            }
                        })
                        root.invalidate()
                    }
                    org.junit.Assert.assertTrue(drawn.await(10, java.util.concurrent.TimeUnit.SECONDS))
                    instrumentation.waitForIdleSync()
                    instrumentation.runOnMainSync {
                        val start = SystemClock.elapsedRealtime()
                        back.invoke(activity)
                        org.junit.Assert.assertSame(originalHome, homeField.get(activity))
                        println("WATCH_PERF route=$page iteration=$iteration back_ms=${SystemClock.elapsedRealtime() - start}")
                    }
                    instrumentation.waitForIdleSync()
                }
            }
            instrumentation.runOnMainSync {
                val start = SystemClock.elapsedRealtime()
                result.invoke(activity, 31, android.app.Activity.RESULT_OK, Intent().putStringArrayListExtra(
                    RecognizerIntent.EXTRA_RESULTS, arrayListOf("")))
                println("WATCH_PERF speech_return_ms=${SystemClock.elapsedRealtime() - start} tasks=${repo.store.tasks().size}")
            }
            instrumentation.waitForIdleSync()
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
