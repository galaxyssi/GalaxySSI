package com.galaxyssi.chat

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentForegroundReloadDeviceTest {
    @Test fun foregroundRestoreDoesNotWaitForTheAgentMonitorOnTheUiThread() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)) as MainActivity
        val handler = Handler(Looper.getMainLooper())
        val executor = Executors.newSingleThreadExecutor()
        val held = CountDownLatch(1)
        val release = CountDownLatch(1)
        try {
            val deadline = SystemClock.elapsedRealtime() + 30_000
            var hydrated = false
            while (!hydrated && SystemClock.elapsedRealtime() < deadline) {
                instrumentation.runOnMainSync { hydrated = !activity.initialAgentHydrationPending }
                if (!hydrated) SystemClock.sleep(50)
            }
            assertTrue("Initial hydration did not finish", hydrated)
            val runtime = activity.mobileNativeAgent
            val writer = executor.submit {
                synchronized(runtime) { held.countDown(); release.await(6, TimeUnit.SECONDS) }
            }
            assertTrue(held.await(2, TimeUnit.SECONDS))
            val responsive = CountDownLatch(1)
            handler.post {
                activity.requestForegroundAgentReload()
                handler.post { responsive.countDown() }
            }
            assertTrue("UI waited for the Agent monitor during foreground restoration",
                responsive.await(500, TimeUnit.MILLISECONDS))
            instrumentation.runOnMainSync { activity.foregroundAgentReload.invalidate() }
            release.countDown()
            writer.get(2, TimeUnit.SECONDS)
        } finally {
            release.countDown()
            executor.shutdownNow()
            executor.awaitTermination(5, TimeUnit.SECONDS)
            instrumentation.runOnMainSync { activity.foregroundAgentReload.invalidate(); activity.finish() }
        }
    }
}
