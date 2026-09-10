package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in metadata-only inspection, restricted to the conversations in the live fixture report. */
@RunWith(AndroidJUnit4::class)
class AgentBackgroundRecoveryInspectionTest {
    @Test fun inspectLastS26LiveRun() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("inspect_background_recovery") == "true")
        assertEquals("SM-S9480", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = context.getExternalFilesDir("window-stress")
        val report = JSONObject(File(directory, "report.json").readText())
        require(report.getString("test_id").startsWith("stress-"))
        require(report.getString("device") == Build.MODEL)
        val runs = report.getJSONArray("runs")
        val conversations = (0 until runs.length()).map { runs.getJSONObject(it).getString("conversation_id") }.toSet()
        require(conversations.size == 10)
        val deliveries = mutableListOf<AgentPendingDelivery>()
        var before: Long? = null
        do {
            val page = AgentPendingDeliveryStore.page(context, before)
            deliveries += page.deliveries.filter { it.conversationId in conversations }
            before = page.nextBeforeSource
        } while (before != null)
        val states = JSONArray(deliveries.map { delivery ->
            val snapshot = SharedPreferencesAgentSessionStore(context, "task:${delivery.turnId}").load()
            JSONObject().put("source", delivery.sourceMessageId.toString())
                .put("conversation", delivery.conversationId).put("turn", delivery.turnId)
                .put("phase", snapshot?.phase?.name).put("binding", AndroidAgentRemoteRecovery.hasCurrentBinding(context, delivery))
                .put("result_metadata", JSONObject(snapshot?.lastActionResult?.metadata.orEmpty()))
        })
        val incoming = GalaxySSILinkDeliveryStore.pendingIncoming(context).mapNotNull { item ->
            val payload = JSONObject(item.payload)
            if (payload.optString("conversation_id") !in conversations) return@mapNotNull null
            JSONObject().put("message_id", item.messageId).put("created_at", item.createdAt)
                .put("fields", JSONObject(listOf("type", "task_id", "source_message_id", "conversation_id",
                    "turn_id", "contact_id", "task_status", "execution_generation", "status_seq", "status_sequence")
                    .associateWith { payload.opt(it) }))
                .put("registered", AgentTaskIdentityStore.matchesRegistered(context, payload))
                .put("observation_decodable", AgentRemoteOutcomeCodec.observation(payload) != null)
        }
        val transcript = AgentTranscriptStore(context)
        val results = JSONArray(conversations.map { conversation ->
            JSONObject().put("conversation", conversation).put("entries", JSONArray(transcript.list(conversation).map {
                JSONObject().put("role", it.role.name).put("characters", it.text.length).put("dedupe_key", it.dedupeKey)
            }))
        })
        val markers = (0 until runs.length()).map { runs.getJSONObject(it).getString("marker") }
        val checks = JSONArray((0 until runs.length()).map { index ->
            val run = runs.getJSONObject(index)
            val entries = transcript.list(run.getString("conversation_id"))
            val answers = entries.filter { it.role == AgentTranscriptRole.ASSISTANT }
            val text = answers.lastOrNull()?.text.orEmpty()
            val marker = run.getString("marker")
            val seed = run.getInt("index") * 100
            val rows = Regex("(?m)^\\s*(\\d+):\\s*(\\d+)\\s*$").findAll(text)
                .map { it.groupValues[1].toInt() to it.groupValues[2].toInt() }
                .filter { (i, result) -> i in 1..80 && result == i + seed }.map { it.first }.toSet().size
            JSONObject().put("index", run.getInt("index")).put("assistant_count", answers.size)
                .put("correct_rows", rows).put("has_own_marker", marker in text)
                .put("has_end_marker", "END $marker" in text)
                .put("foreign_marker", markers.any { it != marker && it in text })
                .put("delivery_failure", entries.any { it.dedupeKey.startsWith("delivery-failed:") })
        })
        File(directory, "recovery-inspection.json").writeText(JSONObject().put("states", states)
            .put("pending_incoming", JSONArray(incoming)).put("transcripts", results)
            .put("result_checks", checks).put("inspected_at", System.currentTimeMillis()).toString(2))
    }
}
