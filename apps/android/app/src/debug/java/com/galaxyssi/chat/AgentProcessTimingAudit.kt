package com.galaxyssi.chat

import android.content.Context
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Isolated real-SQLite check; no user conversation, model call or foreground UI. */
internal fun verifyAgentProcessTiming(context: Context): JSONObject {
    val fixtureId = UUID.randomUUID().toString()
    val databaseName = "debug-process-timing-$fixtureId.db"
    var database = AgentTranscriptEntryDatabase(context, databaseName)
    val conversation = "timing-conversation"
    val turn = "timing-turn"
    val user = AgentTranscriptEntry("user", AgentTranscriptRole.USER, "Synthetic document request", 1_000L,
        conversationId = conversation, turnId = turn, taskId = "runtime-task")
    try {
        check(database.insert(user))
        repeat(46) { index ->
            check(database.insert(user.copy(id = "step-$index", role = AgentTranscriptRole.PROCESS,
                text = "Synthetic tool step $index", timestampMillis = 1_000L + (index + 1) * 3_000L)))
        }
        check(database.insert(user.copy(id = "final", role = AgentTranscriptRole.ASSISTANT,
            text = "Synthetic result", timestampMillis = 151_000L)))
        val page = database.listConversationPage(conversation, pageSize = 24)
        check(page.entries.size == 24 && page.entries.none { it.role == AgentTranscriptRole.USER })
        val process = page.entries.first()
        val startedAt = requireNotNull(database.firstTimestampForTurn(conversation, turn))
        check(AgentProcessClockPolicy.startedAt(process, page.entries, process.timestampMillis, startedAt) == 1_000L)
        check(AgentProcessClock(startedAt, 151_000L).elapsed(999_000L) == 150_000L)
        check(database.insert(user.copy(id = "other-conversation", conversationId = "other", timestampMillis = 10L)))
        check(database.insert(user.copy(id = "other-turn", turnId = "other", timestampMillis = 20L)))
        check(database.insert(user.copy(id = "invalid-time", timestampMillis = 0L)))
        check(database.firstTimestampForTurn(conversation, turn) == 1_000L)
        check(database.firstTimestampForTurn("missing", turn) == null)
        check(database.firstTimestampForTurn(conversation, "") == null)
        database.close()
        database = AgentTranscriptEntryDatabase(context, databaseName)
        check(database.firstTimestampForTurn(conversation, turn) == 1_000L)
        return JSONObject().put("fixture_id", fixtureId).put("passed", true)
            .put("visible_rows", page.entries.size).put("full_elapsed_ms", 150_000L)
            .put("paged_elapsed_ms", 151_000L - process.timestampMillis)
            .put("cases", JSONArray(listOf("paged_start_restored", "terminal_clock_frozen",
                "conversation_and_turn_isolation", "missing_and_invalid_timestamp", "database_reopen")))
    } finally {
        database.close()
        check(context.deleteDatabase(databaseName)) { "Timing fixture cleanup failed" }
    }
}
