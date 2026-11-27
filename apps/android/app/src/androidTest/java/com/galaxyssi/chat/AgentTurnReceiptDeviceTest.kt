package com.galaxyssi.chat

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AgentTurnReceiptDeviceTest {
    private val runner get() = InstrumentationRegistry.getInstrumentation()
    private val target get() = runner.targetContext
    private fun read(chat: String, turn: String): JSONObject {
        val latch = CountDownLatch(1)
        var result: JSONObject? = null
        AgentTurnReceipt.read(target, chat, turn) { result = it; latch.countDown() }
        assertTrue(latch.await(15, TimeUnit.SECONDS))
        return requireNotNull(result)
    }
    private fun payload(chat: String, turn: String, generation: Int = 1, attempt: Int = 1,
        task: String = "task"): JSONObject = JSONObject().put("conversation_id", chat).put("turn_id", turn)
        .put("task_id", task).put("execution_generation", generation).put("type", "agent_task_event")
        .put("delivery_trace", JSONArray().put(JSONObject().put("stage", "desktop_mqtt_received").put("at", 123456)))
        .put("progress_event", JSONObject().put("kind", "agent").put("event_id", "provider:$task:${attempt - 1}")
            .put("metadata", JSONObject().put("provider", "codex").put("attempt", attempt)
                .put("execution_generation", generation).put("model", "submitted-$attempt").put("reasoning_effort", "high")))

    @Test fun duplicateAndOutOfOrderEventsNeverInventModelOrReplaceNewerAttempt() {
        val chat = UUID.randomUUID().toString()
        val turn = "turn"
        try {
            AgentTurnReceipt.begin(target, chat, turn, AgentModelSelection(modelId = "request-only"))
            AgentTurnReceipt.outbound(target, chat, turn, "task", "configured", AgentModelReasoningEffort.XHIGH)
            AgentTurnReceipt.authenticated(target, payload(chat, turn, attempt = 2))
            AgentTurnReceipt.authenticated(target, payload(chat, turn))
            AgentTurnReceipt.authenticated(target, payload(chat, turn, task = "stale"))
            val r = read(chat, turn)
            assertEquals("request-only", r.getString("request"))
            assertEquals("configured", r.getString("wire"))
            assertEquals("submitted-2", r.getString("submitted"))
            assertFalse(r.has("cloud_actual")); assertFalse(r.has("body")); assertFalse(r.has("phone_executed"))
            assertEquals(123456L, r.getLong("desktop_received"))
            AgentTurnReceipt.authenticated(target, payload(chat, turn, 2).also { it.remove("progress_event") })
            assertFalse(read(chat, turn).has("submitted"))
            AgentTurnReceipt.authenticated(target, payload(chat, turn))
            assertFalse(read(chat, turn).has("submitted"))
            AgentTurnReceipt.painted(target, chat, turn)
            val painted = read(chat, turn)
            assertTrue(painted.getLong("body_ms") >= 0)
            AgentTurnReceipt.painted(target, chat, turn)
            assertEquals(painted.getLong("body"), read(chat, turn).getLong("body"))
            assertEquals(0, read("other-$chat", turn).length())
        } finally { AgentTurnReceipt.delete(target, chat) }
        AgentTurnReceipt.authenticated(target, payload(chat, turn))
        assertEquals(0, read(chat, turn).length())
    }

    @Test fun onlyCurrentProviderResponseCanAttestToCloudModelAndEffort() {
        val chat = UUID.randomUUID().toString()
        val turn = "synthetic-turn"
        val request = AgentModelRequest("s", chat, turn, "task", "w", 1, emptyList(), "", "", 2, 400, 1000, 1,
            AgentNativeToolCancellationToken.NONE)
        try {
            AgentTurnReceipt.begin(target, chat, turn, AgentModelSelection(modelId = "my-choice"))
            val earlier = AgentTurnReceipt.cloudStarted(target, request, "cloud-a")
            val current = AgentTurnReceipt.cloudStarted(target, request, "cloud-b")
            AgentTurnReceipt.cloudResponse(target, request, earlier, "stale", "high")
            assertFalse(read(chat, turn).has("cloud_actual"))
            AgentTurnReceipt.cloudResponse(target, request, current, "provider-reported", null)
            val row = read(chat, turn)
            assertEquals("cloud-b", row.getString("cloud_request"))
            assertEquals("provider-reported", row.getString("cloud_actual"))
            assertEquals("", row.optString("cloud_effort"))
            assertFalse(row.has("phone_executed"))
        } finally { AgentTurnReceipt.delete(target, chat) }
    }

    @Test fun tappingElapsedLabelOpensScopedDetailAndReturnsToSameConversation() {
        assumeTrue(target.packageName.endsWith(".pairingqa"))
        val store = AgentTranscriptStore(target, "receipt-device-fixture")
        val chat = store.createConversation("Synthetic receipt").id
        val turn = UUID.randomUUID().toString()
        var activity: MainActivity? = null
        fun texts(v: View): List<TextView> = when (v) {
            is TextView -> listOf(v)
            is ViewGroup -> (0 until v.childCount).flatMap { texts(v.getChildAt(it)) }
            else -> emptyList()
        }
        try {
            AgentTurnReceipt.begin(target, chat, turn, AgentModelSelection(AgentModelSelectionMode.MANUAL,
                modelId = "receipt-fixture", reasoningEffort = AgentModelReasoningEffort.HIGH))
            store.append(AgentTranscriptRole.USER, "Synthetic question", conversationId = chat, turnId = turn)
            store.append(AgentTranscriptRole.PROCESS, "Synthetic step", conversationId = chat, turnId = turn, taskId = turn)
            store.append(AgentTranscriptRole.ASSISTANT, "Synthetic answer", conversationId = chat, turnId = turn, taskId = turn)
            val a = runner.startActivitySync(Intent(target, HealthAtlasDiscussionActivity::class.java)
                .putExtra("galaxyssi_agent_conversation_id", chat).putExtra("galaxyssi_open_agent", true)
                .putExtra(AgentConversationWindows.WINDOW_KEY, "test:$chat")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity = a
            val until = android.os.SystemClock.elapsedRealtime() + 15000
            var tapped = false
            do {
                runner.runOnMainSync {
                    val visible = texts(a.window.decorView)
                    val answerReady = visible.any { it.isShown && it.text.toString().contains("Synthetic answer") }
                    val label = visible.firstOrNull {
                        it.isClickable && it.isShown && it.tag == "turn-receipt:$turn"
                    }
                    tapped = answerReady && label?.performClick() == true
                }
                if (!tapped) Thread.sleep(100)
            } while (!tapped && android.os.SystemClock.elapsedRealtime() < until)
            assertTrue("Real process row has a clickable elapsed-time label", tapped)
            var closed = false
            repeat(80) {
                if (!closed) {
                    runner.runOnMainSync {
                        val dialog = WindowInspector.getGlobalWindowViews().firstOrNull { view ->
                            view.findViewById<View>(android.R.id.button1) != null &&
                                texts(view).any { it.text.toString().contains("receipt-fixture") }
                        }
                        if (dialog != null) {
                            assertTrue(texts(dialog).any { it.text == a.getString(R.string.turn_receipt_missing) })
                            closed = dialog.findViewById<View>(android.R.id.button1).performClick()
                        }
                    }
                    if (!closed) Thread.sleep(100)
                }
            }
            assertTrue("Close the detail without navigating away", closed)
            runner.waitForIdleSync()
            runner.runOnMainSync {
                assertTrue("The original answer is still on screen", texts(a.window.decorView).any {
                    it.isShown && it.text.toString().contains("Synthetic answer")
                })
            }
            val deadline = android.os.SystemClock.elapsedRealtime() + 5000
            while (!read(chat, turn).has("body") && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
            assertTrue("An actual draw of the answer was recorded", read(chat, turn).has("body"))
        } finally {
            activity?.let { runner.runOnMainSync { it.finish() } }
            store.deleteConversation(chat)
        }
    }
}
