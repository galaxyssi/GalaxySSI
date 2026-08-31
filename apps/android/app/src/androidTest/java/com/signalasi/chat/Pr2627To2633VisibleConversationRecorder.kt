package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal data class Pr2627To2633CaseExecution(
    val case: JSONObject,
    val passed: Boolean,
    val durationMillis: Long,
    val failure: String
)

internal data class Pr2627To2633ConversationPersistence(
    val requestedCount: Int,
    val persistedCount: Int,
    val existingConversationCountBefore: Int,
    val totalConversationCountAfter: Int,
    val durationMillis: Long
)

internal object Pr2627To2633VisibleConversationRecorder {
    fun persist(
        context: Context,
        executions: List<Pr2627To2633CaseExecution>
    ): Pr2627To2633ConversationPersistence {
        check(executions.size == 1_000) { "Exactly 1000 visible test conversations are required" }
        check(executions.map { it.case.getString("risk_id") }.distinct().size == executions.size)
        check(executions.map { it.case.getString("conversation_id") }.distinct().size == executions.size)

        val started = System.nanoTime()
        val conversationDatabase = AgentConversationDatabase(context)
        val transcriptDatabase = AgentTranscriptEntryDatabase(context)
        return try {
            val existingCount = conversationDatabase.count()
            val timestampBase = System.currentTimeMillis() - executions.size * TIMESTAMP_STEP_MILLIS
            val transcriptEntries = ArrayList<AgentTranscriptEntry>(executions.size * 2)
            val conversations = executions.mapIndexed { index, execution ->
                val case = execution.case
                val conversationId = case.getString("conversation_id")
                val riskId = case.getString("risk_id")
                val turnId = "$conversationId-turn"
                val taskId = "$conversationId-task"
                val userEntryId = "$conversationId-user"
                val resultEntryId = "$conversationId-result"
                val userTimestamp = timestampBase + index * TIMESTAMP_STEP_MILLIS
                val resultTimestamp = userTimestamp + 1L
                val specification = buildSpecification(case)
                val result = buildResult(case, execution)
                transcriptEntries += AgentTranscriptEntry(
                    id = userEntryId,
                    role = AgentTranscriptRole.USER,
                    text = specification,
                    timestampMillis = userTimestamp,
                    dedupeKey = "regression-specification:$riskId",
                    conversationId = conversationId,
                    turnId = turnId,
                    taskId = taskId
                )
                transcriptEntries += AgentTranscriptEntry(
                    id = resultEntryId,
                    role = AgentTranscriptRole.ASSISTANT,
                    text = result,
                    timestampMillis = resultTimestamp,
                    dedupeKey = "regression-result:$riskId",
                    conversationId = conversationId,
                    turnId = turnId,
                    taskId = taskId
                )
                AgentConversation(
                    id = conversationId,
                    title = "测试 ${case.getString("title_zh")}".take(AgentConversationDatabase.MAX_TITLE_CHARACTERS),
                    createdAt = userTimestamp,
                    updatedAt = resultTimestamp,
                    selectedModelOrAgent = "SM-G9880 真机回归",
                    contextPolicy = "isolated-regression",
                    summary = case.getString("risk_zh"),
                    status = AgentConversationStatus.ACTIVE,
                    privateMode = true,
                    trackingPaused = true,
                    latestMessageIndexed = true,
                    latestMessageEntryId = resultEntryId,
                    latestMessagePreview = result.take(AgentConversationDatabase.MAX_MESSAGE_PREVIEW_CHARACTERS),
                    latestMessageTimestampMillis = resultTimestamp
                )
            }

            check(transcriptDatabase.replaceBatch(transcriptEntries)) {
                "Could not persist the visible regression transcripts"
            }
            check(conversationDatabase.upsertAll(conversations)) {
                "Could not persist the visible regression conversations"
            }

            val persistedCount = conversations.count { expected ->
                val storedConversation = conversationDatabase.read(expected.id)
                val storedEntries = transcriptDatabase.listConversation(expected.id)
                storedConversation?.title == expected.title &&
                    storedConversation.privateMode &&
                    storedConversation.trackingPaused &&
                    storedConversation.latestMessageEntryId == expected.latestMessageEntryId &&
                    storedEntries.map(AgentTranscriptEntry::id).containsAll(
                        listOf("${expected.id}-user", "${expected.id}-result")
                    )
            }
            check(persistedCount == executions.size) {
                "Only $persistedCount/${executions.size} visible conversations were verified"
            }
            Pr2627To2633ConversationPersistence(
                requestedCount = executions.size,
                persistedCount = persistedCount,
                existingConversationCountBefore = existingCount,
                totalConversationCountAfter = conversationDatabase.count(),
                durationMillis = (System.nanoTime() - started) / 1_000_000L
            )
        } finally {
            transcriptDatabase.close()
            conversationDatabase.close()
        }
    }

    private fun buildSpecification(case: JSONObject): String = buildString {
        appendLine("${case.getString("risk_id")} · PR #${case.getInt("pr")}")
        appendLine(case.getString("title_zh"))
        appendLine()
        appendLine("风险：${case.getString("risk_zh")}")
        appendLine("前置条件：")
        case.getJSONArray("preconditions_zh").strings().forEachIndexed { index, value ->
            appendLine("${index + 1}. $value")
        }
        appendLine("操作步骤：")
        case.getJSONArray("steps_zh").strings().forEachIndexed { index, value ->
            appendLine("${index + 1}. $value")
        }
        appendLine("预期结果：")
        case.getJSONArray("expected_zh").strings().forEachIndexed { index, value ->
            appendLine("${index + 1}. $value")
        }
        append("生产代码断言：${case.getString("oracle")}")
    }

    private fun buildResult(
        case: JSONObject,
        execution: Pr2627To2633CaseExecution
    ): String = buildString {
        append(if (execution.passed) "通过" else "失败")
        append(" · ${case.getString("risk_id")}")
        appendLine(" · ${execution.durationMillis} ms")
        append("已执行真实生产代码断言：${case.getString("oracle")}")
        if (execution.failure.isNotBlank()) {
            appendLine()
            append("失败详情：${execution.failure.take(4_000)}")
        }
    }

    private fun JSONArray.strings(): List<String> = (0 until length()).map(::getString)

    private const val TIMESTAMP_STEP_MILLIS = 4L
}
