package com.galaxyssi.chat

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.thread

/** Opt-in real-provider probe. The default test suite never sends a model request. */
@RunWith(AndroidJUnit4::class)
class AgentReplyUiQueueProbeTest {
    @Test fun sampleMainThreadWhileWaitingForRealReply() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_reply_probe") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val token = "reply-queue-probe-${UUID.randomUUID()}"
        val running = AtomicBoolean(true)
        val pendingAt = AtomicLong(0L)
        val handler = Handler(Looper.getMainLooper())
        val monitor = thread(name = "reply-ui-test-probe", isDaemon = true) {
            var lastSampleAt = 0L
            while (running.get()) {
                val now = SystemClock.elapsedRealtime()
                val pending = pendingAt.get()
                if (pending == 0L && pendingAt.compareAndSet(0L, now)) {
                    handler.post { pendingAt.compareAndSet(now, 0L) }
                } else if (pending != 0L && now - pending >= 250L && now - lastSampleAt >= 1_000L) {
                    lastSampleAt = now
                    val frames = Looper.getMainLooper().thread.stackTrace.take(36).joinToString("\n")
                    Log.i(TAG, "queue_wait_ms=${now - pending}\n$frames")
                }
                Thread.sleep(100L)
            }
        }
        try {
            val prompt = "\u8bf7\u7528\u4e00\u53e5\u8bdd\u8bf4\u660e\u6c34\u4e3a\u4ec0\u4e48\u4f1a\u7ed3\u51b0\u3002"
            context.startActivity(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra("galaxyssi_debug_agent_goal_b64", Base64.encodeToString(prompt.toByteArray(), Base64.NO_WRAP))
                .putExtra("galaxyssi_debug_agent_token", token)
                .putExtra("galaxyssi_debug_agent_new_conversation", true))
            Log.i(TAG, "probe_token=$token")
            val deadline = SystemClock.elapsedRealtime() + 120_000L
            val prefs = context.getSharedPreferences("galaxyssi_debug_agent", 0)
            var completed = false
            while (SystemClock.elapsedRealtime() < deadline) {
                val snapshot = prefs.getString(token, null)?.let(::JSONObject)
                if (snapshot?.optBoolean("complete") == true) {
                    Log.i(TAG, "probe_completed phase=${snapshot.optString("phase")}")
                    completed = true
                    break
                }
                Thread.sleep(250L)
            }
            assertTrue("Real reply did not complete; inspect the named probe before retrying", completed)
        } finally {
            running.set(false)
            monitor.join(2_000L)
        }
    }

    companion object { private const val TAG = "ReplyUiQueueProbe" }
}
