package com.galaxyssi.chat

import android.app.ActivityManager
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.SystemClock
import android.view.KeyEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in, real composer -> configured Codex -> MQTT -> durable result stress test. */
@RunWith(AndroidJUnit4::class)
class AgentWindowLiveConcurrencyTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val manager get() = context.getSystemService(ActivityManager::class.java)
    private val runs = CopyOnWriteArrayList<Run>()
    private val events = CopyOnWriteArrayList<JSONObject>()
    private val samples = mutableListOf<JSONObject>()
    private val background = AtomicBoolean(false)
    private var peakRemoteRunning = 0
    private var homeAt = 0L
    private var closedAt = 0L
    private var batchStart = 0L
    private var batchEnd = 0L
    private val testId = "stress-${UUID.randomUUID()}"

    private class Run(val index: Int, val windowKey: String, val conversationId: String, val marker: String) {
        var window: MainActivity? = null
        @Volatile var submittedAt = 0L
        @Volatile var remoteStatus = ""
        @Volatile var reply = ""
        @Volatile var receivedAt = 0L
        @Volatile var receivedInBackground = false
        var renderedAfterReturn = false
        val seed get() = index * 100
    }

    private val observer = object : GalaxySSIMqttClient.Listener {
        override fun onMessage(payload: String) {
            val json = runCatching { JSONObject(payload) }.getOrNull() ?: return
            val run = runs.firstOrNull { it.conversationId == json.optString("conversation_id") } ?: return
            val status = json.optString("task_status")
            val type = json.optString("type")
            if (status.isNotBlank()) run.remoteStatus = status
            synchronized(this@AgentWindowLiveConcurrencyTest) {
                peakRemoteRunning = maxOf(peakRemoteRunning, runs.count { it.remoteStatus == "running" && it.receivedAt == 0L })
            }
            events += JSONObject().put("run", run.index).put("received_at", System.currentTimeMillis())
                .put("source_updated_at", json.optLong("updated_at"))
                .put("type", type).put("status", status).put("background", background.get())
                .put("agent_id", json.optString("agent_id"))
                .put("model", json.optString("model_id")).put("sequence", json.optLong("status_sequence", -1L))
        }
    }

    @Test fun inspectPreviousStressResults() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("inspect_live_stress") == "true")
        assertEquals("SM-T575", Build.MODEL)
        val directory = context.getExternalFilesDir("window-stress")
        val previous = JSONObject(File(directory, "report.json").readText())
        val store = AgentTranscriptStore(context, testId)
        val details = JSONArray()
        val previousRuns = previous.getJSONArray("runs")
        for (i in 0 until previousRuns.length()) {
            val run = previousRuns.getJSONObject(i)
            val entries = store.list(run.getString("conversation_id"))
            details.put(JSONObject().put("index", run.getInt("index"))
                .put("assistant_contains_marker", entries.any {
                    it.role == AgentTranscriptRole.ASSISTANT && run.getString("marker") in it.text
                })
                .put("entries", JSONArray(entries.map {
                    JSONObject().put("role", it.role.name).put("text", it.text)
                        .put("turn_id", it.turnId).put("dedupe_key", it.dedupeKey)
                })))
        }
        File(directory, "stored-results.json").writeText(details.toString(2))
        assertEquals("All real responses remain in their conversation transcripts", 10,
            (0 until details.length()).count { details.getJSONObject(it).getBoolean("assistant_contains_marker") })
    }

    @Test fun tenRealCodexRequestsWhileBackgrounded() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("run_live_stress") == "true")
        assertEquals("This test must only operate SM-T575", "SM-T575", Build.MODEL)
        val target = AppStoreAgentConnectorRegistry(context).availableTargets()
            .filter { it.kind == AgentConnectorKind.AGENT && it.status == AgentConnectorStatus.AVAILABLE &&
                ("codex" in it.id.lowercase() || "codex" in it.title.lowercase()) }
            .sortedBy { if (it.id == "codex") 1 else 0 }.firstOrNull()
            ?: error("No available paired Codex Agent")
        val model = target.invocationProfile.normalizedModelId("")
        val startedAt = System.currentTimeMillis()
        var failure = ""
        GalaxySSIMqttClient.addListener(observer)
        try {
            for (index in 1..10) {
                val key = "$testId-$index"
                val store = AgentTranscriptStore(context, key)
                val conversation = store.createConversation("Codex stress $index", privateMode = true)
                store.append(AgentTranscriptRole.PROCESS, "Concurrency verification $index", conversationId = conversation.id)
                AgentModelSelectionSettings.selectManual(context, conversation.id, target.id, model, target.title,
                    rememberAsDefault = false)
                val run = Run(index, key, conversation.id, "RUN-${UUID.randomUUID().toString().take(8)}")
                runs += run
                run.window = launch(run)
            }
            assertEquals(10, runs.map { it.window!!.taskId }.distinct().size)
            sample()
            batchStart = System.currentTimeMillis()
            instrumentation.runOnMainSync {
                runs.forEach { run ->
                    run.submittedAt = System.currentTimeMillis()
                    run.window!!.agentGoalInput.setText(prompt(run))
                    assertTrue(run.window!!.agentSubmitButton.performClick())
                }
            }
            batchEnd = System.currentTimeMillis()
            await("first real task submitted", 60_000) {
                AgentTaskRuntime.supervisor(context).activeWorkspaces().any { it.conversationId == runs.first().conversationId }
            }
            // Visit another document before returning to Home, without cancelling any run.
            manager.appTasks.first { it.taskInfo.taskId == runs[4].window!!.taskId }.moveToFront()
            await("alternate window resumed") { runs[4].window!!.conversationWindow.visible }
            instrumentation.runOnMainSync { runs.first().window!!.finishAndRemoveTask() }
            closedAt = System.currentTimeMillis()
            await("first window destroyed") { runs.first().window!!.isDestroyed }
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_HOME)
            await("all windows backgrounded") { runs.none { it.window?.conversationWindow?.visible == true } }
            background.set(true)
            homeAt = System.currentTimeMillis()
            capture("background-home.png")
            val deadline = SystemClock.elapsedRealtime() + 600_000
            while (SystemClock.elapsedRealtime() < deadline && runs.any { it.receivedAt == 0L }) {
                collectReplies()
                sample()
                report(target.title, model, startedAt, "running")
                android.util.Log.i("GalaxySSIWindowStress", "received=${runs.count { it.receivedAt > 0 }}/10 " +
                    "remote_running=${runs.count { it.remoteStatus == "running" && it.receivedAt == 0L }} peak=$peakRemoteRunning background=${background.get()}")
                SystemClock.sleep(2_000)
            }
            collectReplies()
            background.set(false)
            runs.forEach { run ->
                if (run.window?.isDestroyed != false) run.window = launch(run)
                else manager.appTasks.firstOrNull { it.taskInfo.taskId == run.window!!.taskId }?.moveToFront()
                await("window ${run.index} resumed") { run.window!!.conversationWindow.visible }
                if (run.receivedAt > 0L) {
                    await("reply ${run.index} rendered", 45_000) {
                        run.window!!.agentTranscriptWindow.entries.any { it.role == AgentTranscriptRole.ASSISTANT && run.marker in it.text }
                    }
                    run.renderedAfterReturn = true
                }
            }
            capture("reopened-last-result.png")
            report(target.title, model, startedAt, "completed")
            assertEquals("Ten final model responses", 10, runs.count { it.receivedAt > 0L })
            assertEquals("Ten isolated valid results", 10, runs.count { validRows(it) == 80 && "END ${it.marker}" in it.reply })
            assertTrue("No confirmed remote running overlap of ten; observed $peakRemoteRunning", peakRemoteRunning >= 10)
            assertTrue("No progress received while all windows were backgrounded", events.any { it.optBoolean("background") && it.optString("status") == "running" })
            assertTrue("Closed window did not complete in the background", runs.first().receivedInBackground)
        } catch (error: Throwable) {
            failure = error.toString()
            throw error
        } finally {
            collectReplies()
            report(target.title, model, startedAt, if (failure.isBlank()) "passed" else "failed", failure)
            GalaxySSIMqttClient.removeListener(observer)
            instrumentation.runOnMainSync { runs.mapNotNull { it.window }.filterNot { it.isDestroyed }.forEach { it.finishAndRemoveTask() } }
            // Keep private stress conversations and durable results for diagnosis; do not cancel unrelated work.
        }
    }

    private fun prompt(run: Run): String =
        "Concurrency test. Do not call tools or delegate. Start with BEGIN ${run.marker}. " +
        "Output exactly 80 separate lines, for i from 1 to 80, in the format i:result where result=i+${run.seed}. " +
        "Write every line explicitly; do not use ranges or ellipses. End with END ${run.marker}. No other text."

    private fun validRows(run: Run): Int = Regex("(?m)^\\s*(\\d+):\\s*(\\d+)\\s*$").findAll(run.reply)
        .map { it.groupValues[1].toInt() to it.groupValues[2].toInt() }
        .filter { (i, result) -> i in 1..80 && result == i + run.seed }.map { it.first }.toSet().size

    private fun collectReplies() {
        val pending = AgentConnectorResponseStore.pending(context)
        val store = AgentTranscriptStore(context, testId)
        runs.filter { it.submittedAt > 0L && it.receivedAt == 0L }.forEach { run ->
            val response = pending.firstOrNull { it.conversationId == run.conversationId }
            val text = response?.content ?: store.list(run.conversationId).lastOrNull { it.role == AgentTranscriptRole.ASSISTANT }?.text
            if (!text.isNullOrBlank()) {
                run.reply = text
                run.receivedAt = System.currentTimeMillis()
                run.receivedInBackground = background.get()
            }
        }
    }

    private fun launch(run: Run): MainActivity {
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/${run.windowKey}"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, run.windowKey)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val window = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity ?: error("Window missing")
            await("window hydrated") { !window.initialAgentHydrationPending && window.conversationWindow.conversationId.isNotBlank() }
            return window
        } finally { instrumentation.removeMonitor(monitor) }
    }

    private fun sample() {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        samples += JSONObject().put("at", System.currentTimeMillis()).put("pss_kib", Debug.getPss())
            .put("cpu_ms", android.os.Process.getElapsedCpuTime()).put("background", background.get())
            .put("battery_temperature_tenths_c", battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1))
            .put("plugged", battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1))
            .put("thermal_status", context.getSystemService(PowerManager::class.java).currentThermalStatus)
    }

    private fun report(target: String, model: String, started: Long, status: String, failure: String = "") {
        val result = JSONObject().put("test_id", testId).put("device", Build.MODEL).put("target", target).put("requested_model", model)
            .put("status", status).put("failure", failure).put("started_at", started).put("updated_at", System.currentTimeMillis())
            .put("batch_start", batchStart).put("batch_end", batchEnd).put("home_at", homeAt).put("closed_window_at", closedAt)
            .put("peak_observed_remote_running", peakRemoteRunning).put("events", JSONArray(events)).put("samples", JSONArray(samples))
            .put("runs", JSONArray(runs.map { run -> JSONObject().put("index", run.index).put("conversation_id", run.conversationId)
                .put("marker", run.marker).put("submitted_at", run.submittedAt).put("received_at", run.receivedAt)
                .put("remote_status", run.remoteStatus).put("received_in_background", run.receivedInBackground)
                .put("rendered_after_return", run.renderedAfterReturn).put("correct_rows", validRows(run)).put("reply", run.reply) }))
        File(context.getExternalFilesDir("window-stress"), "report.json").writeText(result.toString(2))
    }

    private fun await(label: String, timeout: Long = 60_000, check: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            instrumentation.runOnMainSync { ready = check() }
            if (ready) return
            SystemClock.sleep(100)
        }
        error("Timed out: $label")
    }

    private fun capture(name: String) {
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
        File(context.getExternalFilesDir("window-stress"), name).outputStream().use {
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }
}
