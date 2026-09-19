package com.galaxyssi.chat

import android.util.Log
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.Assert.assertTrue

/** Opt-in metadata-only audit; does not delete, acknowledge or replay user messages. */
class MqttOutboxAuditDeviceTest {
    @Test fun sendDiagnosticMessage() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_link_send") == "true")
        val desktop = requireNotNull(args.getString("live_desktop_id"))
        val marker = requireNotNull(args.getString("live_link_marker"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        AppStore.ensureInitialized(context)
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it).getString("id") }
            .single { AppStore.isDesktopDeviceContact(context, it) && AppStore.desktopIdForContact(context, it) == desktop }
        GalaxySSIMqttClient.connect(context)
        val deadline = SystemClock.elapsedRealtime() + 60_000
        while (!GalaxySSIMqttClient.isRequestReplyReady() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(250)
        assertTrue("No authenticated peer route", GalaxySSIMqttClient.isRequestReplyReady())
        val id = ChatHistoryStore.appendOutgoing(context, contact, marker)
        assertTrue(GalaxySSIMqttClient.publishPeerMessageResult(marker, contact, clientMessageId = id).accepted)
        val receiptDeadline = SystemClock.elapsedRealtime() + 90_000
        while (GalaxySSILinkDeliveryStore.hasPendingClientSourceMessageId(context, id) &&
            SystemClock.elapsedRealtime() < receiptDeadline) SystemClock.sleep(250)
        assertTrue("No authenticated storage receipt", !GalaxySSILinkDeliveryStore.hasPendingClientSourceMessageId(context, id))
        Log.i("MqttOutboxAudit", "Diagnostic message storage receipt received")
    }

    @Test fun inspectRetryMetadata() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_link_audit") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        GalaxySSILinkOutboxDatabase(context).use { database ->
            val rows = database.readAll()
            val groups = mutableMapOf<String, Int>()
            var oldest = System.currentTimeMillis()
            var maxAttempts = 0
            val sources = mutableMapOf<Long, Int>()
            val contacts = mutableMapOf<String, Int>()
            for (index in 0 until rows.length()) {
                val item = rows.getJSONObject(index)
                val kind = item.optString("transport_traffic", "message") +
                    if (item.optString("contact_id").isBlank()) ":internal" else ":contact"
                groups[kind] = (groups[kind] ?: 0) + 1
                oldest = minOf(oldest, item.optLong("created_at", oldest))
                maxAttempts = maxOf(maxAttempts, item.optInt("attempts"))
                val source = item.optLong("client_source_message_id")
                sources[source] = (sources[source] ?: 0) + 1
                val contact = item.optString("contact_id").ifBlank { "internal" }
                contacts[contact] = (contacts[contact] ?: 0) + 1
            }
            Log.i("MqttOutboxAudit", "count=${rows.length()} groups=$groups maxAttempts=$maxAttempts " +
                "oldestAgeMinutes=${(System.currentTimeMillis() - oldest) / 60_000}")
            Log.i("MqttOutboxAudit", "withoutSource=${sources[0L] ?: 0} distinctSources=${sources.keys.count { it > 0 }} " +
                "topSourceCounts=${sources.entries.sortedByDescending { it.value }.take(12).map { it.value }} " +
                "contactCounts=${contacts.values.sortedDescending()}")
            if (rows.length() > 0) {
                val first = rows.getJSONObject(0)
                Log.i("MqttOutboxAudit", "firstRowKeys=${first.keys().asSequence().toList().sorted()}")
                val wire = runCatching { org.json.JSONObject(first.optString("wire_payload")) }.getOrNull()
                Log.i("MqttOutboxAudit", "wireScheme=${wire?.optString("scheme")} wireType=${wire?.optString("signal_type")} " +
                    "wireBytes=${first.optString("wire_payload").length} missingMessageIds=" +
                    (0 until rows.length()).count { rows.getJSONObject(it).optString("message_id").isBlank() })
            }
            database.readableDatabase.rawQuery("SELECT COUNT(*), MAX(attempts), MIN(attempts) FROM outbox_messages", null).use {
                if (it.moveToFirst()) Log.i("MqttOutboxAudit", "sqlCount=${it.getInt(0)} maxAttempts=${it.getInt(1)} minAttempts=${it.getInt(2)}")
            }
            database.readableDatabase.rawQuery("SELECT status,COUNT(*) FROM outbox_messages GROUP BY status", null).use {
                while (it.moveToNext()) Log.i("MqttOutboxAudit", "status=${it.getString(0)} count=${it.getInt(1)}")
            }
        }
    }

    @Test fun inspectSelectedConversationTiming() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_link_audit") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val transcripts = AgentTranscriptStore(context)
        val title = InstrumentationRegistry.getArguments().getString("live_conversation_title").orEmpty()
        val conversation = if (title.isBlank()) transcripts.activeConversation()
            else transcripts.conversations().first { it.title.startsWith(title) }
        transcripts.list(conversation.id).filter { it.role == AgentTranscriptRole.ASSISTANT &&
            (it.dedupeKey.startsWith("delivery-failed:") || it.text.contains("暂未确认送达")) }.forEach { failure ->
            val session = SharedPreferencesAgentSessionStore(context, "task:${failure.turnId}").load()
            val source = failure.dedupeKey.substringAfter(':').toLongOrNull()
                ?: session?.lastActionResult?.metadata?.get("source_message_id")?.toLongOrNull() ?: return@forEach
            val process = transcripts.entriesForTurn(failure.turnId).filter { it.role == AgentTranscriptRole.PROCESS }
            val start = process.minOfOrNull { it.timestampMillis } ?: failure.timestampMillis
            Log.i("MqttOutboxAudit", "selectedFailure source=$source waitMinutes=${(failure.timestampMillis-start)/60000} " +
                "pending=${AgentPendingDeliveryStore.find(context, source) != null} " +
                "outbox=${GalaxySSILinkDeliveryStore.hasPendingClientSourceMessageId(context, source)} " +
                "terminal=${AgentTerminalDeliveryStore.isTerminal(context, source)}")
        }
    }
}
