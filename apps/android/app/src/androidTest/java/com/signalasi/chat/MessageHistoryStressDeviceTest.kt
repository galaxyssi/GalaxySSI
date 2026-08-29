package com.signalasi.chat

import android.content.Context
import android.os.Debug
import android.os.SystemClock
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
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
        val count = arguments.getString(ARG_COUNT)?.toIntOrNull()?.coerceIn(1, MAX_COUNT) ?: DEFAULT_COUNT
        val cadenceMillis = arguments.getString(ARG_CADENCE_MILLIS)
            ?.toLongOrNull()
            ?.coerceIn(0L, MAX_CADENCE_MILLIS)
            ?: DEFAULT_CADENCE_MILLIS
        val runId = arguments.getString(ARG_RUN_ID).orEmpty().ifBlank {
            System.currentTimeMillis().toString()
        }.replace(Regex("[^A-Za-z0-9_-]"), "_").take(48)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = AgentTranscriptStore(context)
        val report = when (mode) {
            MODE_MANY_CONVERSATIONS -> seedManyConversations(store, runId, count, cadenceMillis)
            MODE_SINGLE_CONVERSATION -> seedSingleConversation(store, runId, count, cadenceMillis)
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
        val contentPrefix = "压力内容-$runId-"
        val elapsedMillis = runCadenced(count, cadenceMillis) { index ->
            val ordinal = index + 1
            val conversation = store.createConversation("$titlePrefix${ordinal.toString().padStart(4, '0')}")
            assertTrue(
                store.append(
                    role = AgentTranscriptRole.USER,
                    text = "$contentPrefix${ordinal.toString().padStart(4, '0')}",
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
        const val MODE_MANY_CONVERSATIONS = "many_conversations"
        const val MODE_SINGLE_CONVERSATION = "single_conversation"
        const val DEFAULT_COUNT = 1_000
        const val MAX_COUNT = 10_000
        const val DEFAULT_CADENCE_MILLIS = 1_000L
        const val MAX_CADENCE_MILLIS = 60_000L
        const val PROGRESS_INTERVAL = 100
    }
}
