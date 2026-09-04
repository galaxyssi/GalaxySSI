package com.galaxyssi.chat

import android.content.Context
import android.os.Debug
import android.os.SystemClock
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.BitSet
import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MessageHistoryStressDeviceTest {
    @Test
    fun conversationPreviewIndexTracksLatestDialogueEntry() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = AgentTranscriptStore(context)
        val conversation = store.createConversation("压力预览索引-${System.currentTimeMillis()}")
        try {
            val userText = "第一行\n第二行"
            assertTrue(
                store.append(
                    role = AgentTranscriptRole.USER,
                    text = userText,
                    conversationId = conversation.id
                )
            )
            val afterUser = store.conversation(conversation.id)!!
            assertTrue(afterUser.latestMessageIndexed)
            assertEquals("第一行 第二行", afterUser.latestMessagePreview)
            assertTrue(afterUser.latestMessageEntryId.isNotBlank())
            assertTrue(afterUser.latestMessageTimestampMillis > 0L)

            assertTrue(
                store.append(
                    role = AgentTranscriptRole.ASSISTANT,
                    text = "第二条消息",
                    conversationId = conversation.id
                )
            )
            val afterAssistant = store.conversation(conversation.id)!!
            assertEquals("第二条消息", afterAssistant.latestMessagePreview)
            assertTrue(afterAssistant.latestMessageEntryId != afterUser.latestMessageEntryId)
            assertTrue(afterAssistant.latestMessageTimestampMillis >= afterUser.latestMessageTimestampMillis)
        } finally {
            store.deleteConversation(conversation.id)
        }
    }

    @Test
    fun seedSyntheticMessageHistoryAtRequestedCadence() {
        val arguments = InstrumentationRegistry.getArguments()
        val mode = arguments.getString(ARG_MODE).orEmpty().ifBlank { MODE_MANY_CONVERSATIONS }
        val maxCount = if (mode in PEER_MODES) MAX_PEER_COUNT else MAX_CONVERSATION_COUNT
        val count = arguments.getString(ARG_COUNT)?.toIntOrNull()?.coerceIn(1, maxCount) ?: DEFAULT_COUNT
        val cadenceMillis = arguments.getString(ARG_CADENCE_MILLIS)
            ?.toLongOrNull()
            ?.coerceIn(0L, MAX_CADENCE_MILLIS)
            ?: DEFAULT_CADENCE_MILLIS
        val runId = arguments.getString(ARG_RUN_ID).orEmpty().ifBlank {
            System.currentTimeMillis().toString()
        }.replace(Regex("[^A-Za-z0-9_-]"), "_").take(48)
        val dispatchTransport = arguments.getString(ARG_DISPATCH_TRANSPORT)
            ?.toBooleanStrictOrNull()
            ?: true
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = AgentTranscriptStore(context)
        val report = when (mode) {
            MODE_MANY_CONVERSATIONS -> seedManyConversations(store, runId, count, cadenceMillis)
            MODE_SINGLE_CONVERSATION -> seedSingleConversation(store, runId, count, cadenceMillis)
            MODE_PEER_CONVERSATION -> seedPeerConversation(
                context = context,
                runId = runId,
                count = count,
                cadenceMillis = cadenceMillis,
                contactQuery = arguments.getString(ARG_CONTACT_QUERY).orEmpty().ifBlank { "S26" },
                dispatchTransport = dispatchTransport
            )
            MODE_CLEANUP_PEER_OUTBOX -> cleanupPeerOutbox(
                context = context,
                runId = runId,
                contactQuery = arguments.getString(ARG_CONTACT_QUERY).orEmpty().ifBlank { "S26" }
            )
            else -> error("Unsupported stress mode: $mode")
        }
        writeReport(context, report)
        Log.i(TAG, "STRESS_REPORT $report")
    }

    private fun seedManyConversations(
        store: AgentTranscriptStore,
        runId: String,
        count: Int,
        cadenceMillis: Long
    ): JSONObject {
        val titlePrefix = "压力会话-$runId-"
        val contentPrefix = "会话压力测试-$runId-"
        val existingByOrdinal = store.conversations(includeArchived = true)
            .filter { it.title.startsWith(titlePrefix) }
            .groupBy { conversation ->
                conversation.title.removePrefix(titlePrefix).toIntOrNull()
            }
        assertTrue("Duplicate stress conversation titles detected", existingByOrdinal.values.all { it.size == 1 })
        val missingOrdinals = (1..count).filter { ordinal ->
            val conversation = existingByOrdinal[ordinal]?.singleOrNull() ?: return@filter true
            store.page(conversation.id, pageSize = 2).entries.none {
                it.dedupeKey == "stress-many:$runId:$ordinal"
            }
        }
        val elapsedMillis = runCadenced(missingOrdinals.size, cadenceMillis) { index ->
            val ordinal = missingOrdinals[index]
            val suffix = ordinal.toString().padStart(5, '0')
            val conversation = existingByOrdinal[ordinal]?.singleOrNull()
                ?: store.createConversation("$titlePrefix$suffix")
            assertTrue(
                store.append(
                    role = AgentTranscriptRole.USER,
                    text = "$contentPrefix$suffix",
                    dedupeKey = "stress-many:$runId:$ordinal",
                    conversationId = conversation.id
                )
            )
        }
        val matching = store.conversations(includeArchived = true).filter { it.title.startsWith(titlePrefix) }
        assertEquals(count, matching.size)
        assertTrue(matching.all { store.page(it.id, pageSize = 2).entries.size == 1 })
        assertTrue(matching.all(AgentConversation::latestMessageIndexed))
        assertTrue(matching.all { it.latestMessagePreview.startsWith(contentPrefix) })
        assertTrue(matching.all { it.latestMessageTimestampMillis > 0L })
        return baseReport(MODE_MANY_CONVERSATIONS, runId, count, cadenceMillis, elapsedMillis)
            .put("resumed_conversations", count - missingOrdinals.size)
            .put("verified_conversations", matching.size)
            .put("verified_messages", matching.sumOf { store.page(it.id, pageSize = 2).entries.size })
    }

    private fun seedSingleConversation(
        store: AgentTranscriptStore,
        runId: String,
        count: Int,
        cadenceMillis: Long
    ): JSONObject {
        val title = "压力单会话-$runId"
        val conversation = store.conversations(includeArchived = true)
            .firstOrNull { it.title == title }
            ?: store.createConversation(title)
        val dedupePrefix = "stress-single:$runId:"
        val existingOrdinals = store.list(conversation.id)
            .mapNotNull { entry ->
                entry.dedupeKey.takeIf { it.startsWith(dedupePrefix) }
                    ?.removePrefix(dedupePrefix)
                    ?.toIntOrNull()
            }
            .toSet()
        val missingOrdinals = (1..count).filterNot(existingOrdinals::contains)
        val elapsedMillis = runCadenced(missingOrdinals.size, cadenceMillis) { index ->
            val ordinal = missingOrdinals[index]
            assertTrue(
                store.append(
                    role = AgentTranscriptRole.USER,
                    text = "单会话压力内容-$runId-${ordinal.toString().padStart(4, '0')}",
                    dedupeKey = "stress-single:$runId:$ordinal",
                    conversationId = conversation.id
                )
            )
        }
        val verifiedEntries = store.list(conversation.id)
            .count { it.dedupeKey.startsWith(dedupePrefix) }
        assertEquals(count, verifiedEntries)
        return baseReport(MODE_SINGLE_CONVERSATION, runId, count, cadenceMillis, elapsedMillis)
            .put("conversation_id", conversation.id)
            .put("resumed_messages", existingOrdinals.size)
            .put("verified_messages", verifiedEntries)
    }

    private fun seedPeerConversation(
        context: Context,
        runId: String,
        count: Int,
        cadenceMillis: Long,
        contactQuery: String,
        dispatchTransport: Boolean
    ): JSONObject {
        AppStore.ensureInitialized(context)
        val contact = findPersonContact(context, contactQuery)
        val contactId = contact.getString("id")
        val contactName = contact.optString("name", contactId)
        val topic = checkNotNull(AppStore.outgoingTopicForContact(context, contactId)) {
            "Verified outgoing route is unavailable for $contactName ($contactId)"
        }
        if (dispatchTransport) {
            GalaxySSIMqttClient.connect(context)
        } else {
            GalaxySSIMqttClient.prepareReliableQueue(context)
        }
        val contentPrefix = "单会话压力测试-$runId-"
        val existing = peerOrdinals(context, contactId, contentPrefix, count)
        val missingOrdinals = (1..count).filterNot(existing::get)
        var published = 0
        var queued = 0
        var failed = 0
        var persistNanos = 0L
        var publishNanos = 0L
        var statusNanos = 0L
        var maxPersistNanos = 0L
        var maxPublishNanos = 0L
        var maxStatusNanos = 0L
        val elapsedMillis = runCadenced(missingOrdinals.size, cadenceMillis) { index ->
            val ordinal = missingOrdinals[index]
            val content = "$contentPrefix${ordinal.toString().padStart(6, '0')}"
            val persistStartedAt = SystemClock.elapsedRealtimeNanos()
            val messageId = ChatHistoryStore.appendOutgoing(
                context = context,
                contactId = contactId,
                content = content,
                deliveryStatus = context.getString(R.string.delivery_status_sending)
            )
            val persistedFor = SystemClock.elapsedRealtimeNanos() - persistStartedAt
            persistNanos += persistedFor
            maxPersistNanos = maxOf(maxPersistNanos, persistedFor)
            assertTrue("Outgoing stress message was not persisted", messageId > 0L)
            val publishStartedAt = SystemClock.elapsedRealtimeNanos()
            val result = GalaxySSIMqttClient.publishPeerMessageResult(
                content = content,
                contactId = contactId,
                topicOverride = topic,
                clientMessageId = messageId,
                dispatchQueued = dispatchTransport
            )
            val publishedFor = SystemClock.elapsedRealtimeNanos() - publishStartedAt
            publishNanos += publishedFor
            maxPublishNanos = maxOf(maxPublishNanos, publishedFor)
            val status = when (result) {
                MqttPublishResult.PUBLISHED -> {
                    published += 1
                    context.getString(R.string.delivery_status_sent)
                }
                MqttPublishResult.QUEUED -> {
                    queued += 1
                    context.getString(R.string.delivery_status_queued)
                }
                MqttPublishResult.FAILED -> {
                    failed += 1
                    context.getString(R.string.delivery_status_failed)
                }
            }
            val statusStartedAt = SystemClock.elapsedRealtimeNanos()
            ChatHistoryStore.markOutgoingDelivery(
                context = context,
                contactId = contactId,
                messageId = messageId,
                stage = "stress_${result.name.lowercase(Locale.US)}",
                detail = topic,
                status = status
            )
            val statusFor = SystemClock.elapsedRealtimeNanos() - statusStartedAt
            statusNanos += statusFor
            maxStatusNanos = maxOf(maxStatusNanos, statusFor)
        }
        val verification = verifyPeerHistory(context, contactId, contentPrefix, count)
        return baseReport(MODE_PEER_CONVERSATION, runId, count, cadenceMillis, elapsedMillis)
            .put("contact_id", contactId)
            .put("contact_name", contactName)
            .put("transport_dispatch_enabled", dispatchTransport)
            .put("resumed_messages", existing.cardinality())
            .put("published_messages", published)
            .put("queued_messages", queued)
            .put("failed_messages", failed)
            .put("persist_average_ms", averageMillis(persistNanos, missingOrdinals.size))
            .put("persist_max_ms", nanosToMillis(maxPersistNanos))
            .put("publish_average_ms", averageMillis(publishNanos, missingOrdinals.size))
            .put("publish_max_ms", nanosToMillis(maxPublishNanos))
            .put("status_average_ms", averageMillis(statusNanos, missingOrdinals.size))
            .put("status_max_ms", nanosToMillis(maxStatusNanos))
            .put("verified_messages", verification.verified)
            .put("verified_unique_ordinals", verification.uniqueOrdinals)
            .put("verified_ordered", verification.ordered)
            .put("outbox_payload_files", File(context.filesDir, "opaque-link-outbox-v2").list()?.size ?: 0)
    }

    private fun findPersonContact(context: Context, query: String): JSONObject {
        val normalizedQuery = query.trim()
        val contacts = AppStore.contacts(context)
        val matches = buildList {
            for (index in 0 until contacts.length()) {
                val contact = contacts.optJSONObject(index) ?: continue
                val id = contact.optString("id").ifBlank { contact.optString("galaxyssi_id") }
                val name = contact.optString("name", id)
                if (
                    id.isNotBlank() &&
                    AppStore.isPersonContact(context, id) &&
                    (normalizedQuery.isBlank() || name.contains(normalizedQuery, ignoreCase = true))
                ) add(contact)
            }
        }
        check(matches.size == 1) {
            "Expected exactly one verified person contact matching '$query', found " +
                matches.joinToString(prefix = "[", postfix = "]") { it.optString("name", it.optString("id")) }
        }
        return matches.single()
    }

    private fun cleanupPeerOutbox(
        context: Context,
        runId: String,
        contactQuery: String
    ): JSONObject {
        AppStore.ensureInitialized(context)
        val contact = findPersonContact(context, contactQuery)
        val contactId = contact.getString("id")
        val contentPrefix = if (runId == ALL_STRESS_RUNS) {
            "单会话压力测试-"
        } else {
            "单会话压力测试-$runId-"
        }
        val sourceMessageIds = buildList {
            forEachPeerMessagePage(context, contactId) { message ->
                if (message.optString("content").startsWith(contentPrefix)) {
                    message.optLong("id", 0L).takeIf { it > 0L }?.let(::add)
                }
            }
        }
        val pendingBefore = GalaxySSILinkDeliveryStore.pendingCount(context)
        val removed = GalaxySSILinkDeliveryStore.discardClientSourceMessages(context, sourceMessageIds)
        val pendingAfter = GalaxySSILinkDeliveryStore.pendingCount(context)
        assertEquals(pendingBefore - removed, pendingAfter)
        return baseReport(MODE_CLEANUP_PEER_OUTBOX, runId, sourceMessageIds.size, 0L, 0L)
            .put("contact_id", contactId)
            .put("matched_source_messages", sourceMessageIds.size)
            .put("removed_outbox_messages", removed)
            .put("outbox_before", pendingBefore)
            .put("outbox_after", pendingAfter)
    }

    private fun peerOrdinals(
        context: Context,
        contactId: String,
        contentPrefix: String,
        count: Int
    ): BitSet {
        val ordinals = BitSet(count + 1)
        forEachPeerMessagePage(context, contactId) { message ->
            parseOrdinal(message.optString("content"), contentPrefix, count)?.let(ordinals::set)
        }
        return ordinals
    }

    private fun verifyPeerHistory(
        context: Context,
        contactId: String,
        contentPrefix: String,
        count: Int
    ): PeerVerification {
        val ordinals = BitSet(count + 1)
        val timestamps = LongArray(count + 1)
        var verified = 0
        var duplicate = false
        forEachPeerMessagePage(context, contactId) { message ->
            val ordinal = parseOrdinal(message.optString("content"), contentPrefix, count)
                ?: return@forEachPeerMessagePage
            duplicate = duplicate || ordinals[ordinal]
            ordinals.set(ordinal)
            timestamps[ordinal] = message.optLong("timestamp", 0L)
            verified += 1
        }
        assertEquals("Peer stress message count mismatch", count, verified)
        assertEquals("Peer stress ordinals are missing or duplicated", count, ordinals.cardinality())
        assertTrue("Duplicate peer stress messages detected", !duplicate)
        val ordered = (2..count).all { ordinal -> timestamps[ordinal] >= timestamps[ordinal - 1] }
        assertTrue("Peer stress messages are out of timestamp order", ordered)
        return PeerVerification(verified, ordinals.cardinality(), ordered)
    }

    private fun forEachPeerMessagePage(
        context: Context,
        contactId: String,
        consume: (JSONObject) -> Unit
    ) {
        var beforeSequence: Long? = null
        do {
            val page = ChatHistoryStore.page(
                context = context,
                contactId = contactId,
                beforeSequenceExclusive = beforeSequence,
                pageSize = PEER_VERIFY_PAGE_SIZE
            )
            page.messages.forEach(consume)
            beforeSequence = page.nextBeforeSequence
        } while (page.hasMore && beforeSequence != null)
    }

    private fun parseOrdinal(content: String, prefix: String, count: Int): Int? =
        content.takeIf { it.startsWith(prefix) }
            ?.removePrefix(prefix)
            ?.toIntOrNull()
            ?.takeIf { it in 1..count }

    private fun averageMillis(totalNanos: Long, count: Int): Double =
        if (count <= 0) 0.0 else totalNanos / count / 1_000_000.0

    private fun nanosToMillis(nanos: Long): Double = nanos / 1_000_000.0

    private data class PeerVerification(
        val verified: Int,
        val uniqueOrdinals: Int,
        val ordered: Boolean
    )

    private fun runCadenced(count: Int, cadenceMillis: Long, operation: (Int) -> Unit): Long {
        val startedAt = SystemClock.elapsedRealtime()
        repeat(count) { index ->
            val scheduledAt = startedAt + index * cadenceMillis
            val waitMillis = scheduledAt - SystemClock.elapsedRealtime()
            if (waitMillis > 0L) SystemClock.sleep(waitMillis)
            operation(index)
            if ((index + 1) % PROGRESS_INTERVAL == 0 || index + 1 == count) {
                Log.i(
                    TAG,
                    "STRESS_PROGRESS ${index + 1}/$count elapsed=${SystemClock.elapsedRealtime() - startedAt}ms " +
                        "pss=${Debug.getPss()}KiB"
                )
            }
        }
        return SystemClock.elapsedRealtime() - startedAt
    }

    private fun baseReport(
        mode: String,
        runId: String,
        count: Int,
        cadenceMillis: Long,
        elapsedMillis: Long
    ): JSONObject = JSONObject()
        .put("mode", mode)
        .put("run_id", runId)
        .put("count", count)
        .put("cadence_ms", cadenceMillis)
        .put("elapsed_ms", elapsedMillis)
        .put("effective_messages_per_second", if (elapsedMillis == 0L) count else count * 1000.0 / elapsedMillis)
        .put("final_pss_kib", Debug.getPss())
        .put("cadence_overrun_ms", (elapsedMillis - cadenceMillis * (count - 1)).coerceAtLeast(0L))

    private fun writeReport(context: Context, report: JSONObject) {
        val directory = File(context.filesDir, "stress-reports")
        check(directory.mkdirs() || directory.isDirectory)
        val mode = report.getString("mode")
        val runId = report.getString("run_id")
        File(directory, "$mode-$runId.json").writeText(report.toString(2))
    }

    private companion object {
        const val TAG = "MessageHistoryStress"
        const val ARG_MODE = "stress_mode"
        const val ARG_COUNT = "stress_count"
        const val ARG_CADENCE_MILLIS = "stress_cadence_ms"
        const val ARG_RUN_ID = "stress_run_id"
        const val ARG_CONTACT_QUERY = "stress_contact_query"
        const val ARG_DISPATCH_TRANSPORT = "stress_dispatch_transport"
        const val MODE_MANY_CONVERSATIONS = "many_conversations"
        const val MODE_SINGLE_CONVERSATION = "single_conversation"
        const val MODE_PEER_CONVERSATION = "peer_conversation"
        const val MODE_CLEANUP_PEER_OUTBOX = "cleanup_peer_outbox"
        const val ALL_STRESS_RUNS = "all"
        val PEER_MODES = setOf(MODE_PEER_CONVERSATION, MODE_CLEANUP_PEER_OUTBOX)
        const val DEFAULT_COUNT = 1_000
        const val MAX_CONVERSATION_COUNT = 10_000
        const val MAX_PEER_COUNT = 100_000
        const val DEFAULT_CADENCE_MILLIS = 1_000L
        const val MAX_CADENCE_MILLIS = 60_000L
        const val PROGRESS_INTERVAL = 100
        const val PEER_VERIFY_PAGE_SIZE = 500
    }
}
