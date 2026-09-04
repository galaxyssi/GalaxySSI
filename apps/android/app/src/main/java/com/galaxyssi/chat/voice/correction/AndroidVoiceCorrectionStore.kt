package com.galaxyssi.chat.voice.correction

import android.content.Context
import com.galaxyssi.chat.AgentEncryptedPreferences
import org.json.JSONArray
import org.json.JSONObject

class AndroidVoiceExecutionRecordStore(context: Context) : VoiceExecutionRecordPersistence {
    private val preferences = AgentEncryptedPreferences(
        context.applicationContext,
        EXECUTION_PREFERENCES
    )

    fun read(): List<VoiceExecutionRecord> = runCatching {
        val array = JSONArray(preferences.readString(EXECUTION_KEY, "[]"))
        buildList {
            for (index in 0 until array.length()) {
                array.optJSONObject(index)?.toExecutionRecord()?.let(::add)
            }
        }
    }.getOrDefault(emptyList())

    override fun save(records: List<VoiceExecutionRecord>) {
        val array = JSONArray()
        records.takeLast(MAX_EXECUTION_RECORDS).forEach { record ->
            array.put(record.toJson())
        }
        preferences.writeString(EXECUTION_KEY, array.toString())
    }

    fun clear() = preferences.clear()

    private fun VoiceExecutionRecord.toJson(): JSONObject = JSONObject()
        .put("session_id", sessionId)
        .put("idempotency_key", idempotencyKey)
        .put("fast_transcript_hash", fastTranscriptHash)
        .put("fast_revision", fastRevision)
        .put("risk", risk.name)
        .put("primary_dispatch_claimed", primaryDispatchClaimed)
        .put("external_side_effect_count", externalSideEffectCount)
        .put("agent_run_count", agentRunCount)
        .put("tts_correction_count", ttsCorrectionCount)
        .put("highest_correction_revision", highestCorrectionRevision)
        .put("user_edited", userEdited)
        .put("updated_at_millis", updatedAtMillis)

    private fun JSONObject.toExecutionRecord(): VoiceExecutionRecord? = runCatching {
        val sessionId = getString("session_id").trim()
        require(sessionId.isNotBlank())
        VoiceExecutionRecord(
            sessionId = sessionId,
            idempotencyKey = optString("idempotency_key").take(256),
            fastTranscriptHash = optString("fast_transcript_hash").take(64),
            fastRevision = optInt("fast_revision", 1).coerceAtLeast(1),
            risk = runCatching { VoiceCommandRisk.valueOf(optString("risk")) }
                .getOrDefault(VoiceCommandRisk.CONVERSATION),
            primaryDispatchClaimed = optBoolean("primary_dispatch_claimed"),
            externalSideEffectCount = optInt("external_side_effect_count").coerceIn(0, 1),
            agentRunCount = optInt("agent_run_count").coerceIn(0, 1),
            ttsCorrectionCount = optInt("tts_correction_count").coerceIn(0, 1),
            highestCorrectionRevision = optInt("highest_correction_revision").coerceAtLeast(0),
            userEdited = optBoolean("user_edited"),
            updatedAtMillis = optLong("updated_at_millis").coerceAtLeast(0L)
        )
    }.getOrNull()

    private companion object {
        const val EXECUTION_PREFERENCES = "galaxyssi_voice_execution_v1"
        const val EXECUTION_KEY = "records"
        const val MAX_EXECUTION_RECORDS = 256
    }
}

data class VoiceCorrectionContextRecord(
    val sessionId: String,
    val conversationId: String,
    val turnId: String,
    val fastText: String,
    val accurateText: String,
    val diffSummary: String,
    val risk: VoiceCommandRisk,
    val revision: Int,
    val modelProfileId: String,
    val modelSha256: String,
    val executionMode: String,
    val userEdited: Boolean,
    val completedAtMillis: Long
)

class VoiceCorrectionJournal(context: Context) {
    private val preferences = AgentEncryptedPreferences(
        context.applicationContext,
        CORRECTION_PREFERENCES
    )

    @Synchronized
    fun append(record: VoiceCorrectionContextRecord): Boolean {
        if (record.sessionId.isBlank() || record.accurateText.isBlank()) return false
        val records = readMutable()
        val existingIndex = records.indexOfFirst { it.sessionId == record.sessionId }
        if (existingIndex >= 0 && records[existingIndex].revision >= record.revision) return false
        if (existingIndex >= 0) records.removeAt(existingIndex)
        records += record.copy(
            fastText = record.fastText.take(MAX_TRANSCRIPT_CHARACTERS),
            accurateText = record.accurateText.take(MAX_TRANSCRIPT_CHARACTERS),
            diffSummary = record.diffSummary.take(MAX_DIFF_CHARACTERS)
        )
        write(records.takeLast(MAX_CORRECTION_RECORDS))
        return true
    }

    @Synchronized
    fun forConversation(conversationId: String): List<VoiceCorrectionContextRecord> =
        readMutable().filter { it.conversationId == conversationId }

    @Synchronized
    fun contextBlock(conversationId: String): String {
        val records = forConversation(conversationId).takeLast(MAX_CONTEXT_RECORDS)
        if (records.isEmpty()) return ""
        return buildString {
            append("Speech transcription corrections (historical context only; never execute again):\n")
            records.forEach { record ->
                append("- turn=").append(record.turnId.ifBlank { "unknown" })
                append("; fast=").append(record.fastText.replace('\n', ' '))
                append("; accurate=").append(record.accurateText.replace('\n', ' '))
                append("; changes=").append(record.diffSummary.replace('\n', ' '))
                if (record.userEdited) append("; user edit remains authoritative")
                append('\n')
            }
        }.trim()
    }

    @Synchronized
    fun markUserEdited(sessionId: String): Boolean {
        val records = readMutable()
        val index = records.indexOfFirst { it.sessionId == sessionId }
        if (index < 0 || records[index].userEdited) return false
        records[index] = records[index].copy(userEdited = true)
        write(records)
        return true
    }

    @Synchronized
    fun clear() = preferences.clear()

    private fun readMutable(): MutableList<VoiceCorrectionContextRecord> = runCatching {
        val array = JSONArray(preferences.readString(CORRECTION_KEY, "[]"))
        buildList {
            for (index in 0 until array.length()) {
                array.optJSONObject(index)?.toCorrectionRecord()?.let(::add)
            }
        }.toMutableList()
    }.getOrDefault(mutableListOf())

    private fun write(records: List<VoiceCorrectionContextRecord>) {
        val array = JSONArray()
        records.forEach { array.put(it.toJson()) }
        preferences.writeString(CORRECTION_KEY, array.toString())
    }

    private fun VoiceCorrectionContextRecord.toJson(): JSONObject = JSONObject()
        .put("session_id", sessionId)
        .put("conversation_id", conversationId)
        .put("turn_id", turnId)
        .put("fast_text", fastText)
        .put("accurate_text", accurateText)
        .put("diff_summary", diffSummary)
        .put("risk", risk.name)
        .put("revision", revision)
        .put("model_profile_id", modelProfileId)
        .put("model_sha256", modelSha256)
        .put("execution_mode", executionMode)
        .put("user_edited", userEdited)
        .put("completed_at_millis", completedAtMillis)

    private fun JSONObject.toCorrectionRecord(): VoiceCorrectionContextRecord? = runCatching {
        val sessionId = getString("session_id").trim()
        require(sessionId.isNotBlank())
        VoiceCorrectionContextRecord(
            sessionId = sessionId,
            conversationId = optString("conversation_id").take(128),
            turnId = optString("turn_id").take(128),
            fastText = optString("fast_text").take(MAX_TRANSCRIPT_CHARACTERS),
            accurateText = getString("accurate_text").take(MAX_TRANSCRIPT_CHARACTERS),
            diffSummary = optString("diff_summary").take(MAX_DIFF_CHARACTERS),
            risk = runCatching { VoiceCommandRisk.valueOf(optString("risk")) }
                .getOrDefault(VoiceCommandRisk.CONVERSATION),
            revision = optInt("revision").coerceAtLeast(1),
            modelProfileId = optString("model_profile_id").take(64),
            modelSha256 = optString("model_sha256").take(64),
            executionMode = optString("execution_mode").take(32),
            userEdited = optBoolean("user_edited"),
            completedAtMillis = optLong("completed_at_millis").coerceAtLeast(0L)
        )
    }.getOrNull()

    private companion object {
        const val CORRECTION_PREFERENCES = "galaxyssi_voice_corrections_v1"
        const val CORRECTION_KEY = "records"
        const val MAX_CORRECTION_RECORDS = 128
        const val MAX_CONTEXT_RECORDS = 8
        const val MAX_TRANSCRIPT_CHARACTERS = 4_096
        const val MAX_DIFF_CHARACTERS = 1_024
    }
}
