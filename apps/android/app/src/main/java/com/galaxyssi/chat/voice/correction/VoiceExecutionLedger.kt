package com.galaxyssi.chat.voice.correction

import com.galaxyssi.chat.voice.TranscriptHypothesis
import java.security.MessageDigest
import java.util.LinkedHashMap

fun interface VoiceExecutionRecordPersistence {
    fun save(records: List<VoiceExecutionRecord>)
}

class VoiceExecutionLedger(
    initialRecords: Collection<VoiceExecutionRecord> = emptyList(),
    private val persistence: VoiceExecutionRecordPersistence? = null,
    private val clock: () -> Long = System::currentTimeMillis,
    private val maxRecords: Int = 256
) {
    private val records = LinkedHashMap<String, VoiceExecutionRecord>()

    init {
        require(maxRecords >= 16)
        initialRecords.sortedBy(VoiceExecutionRecord::updatedAtMillis).forEach { record ->
            if (record.sessionId.isNotBlank()) records[record.sessionId] = record
        }
        trim()
    }

    @Synchronized
    fun begin(
        sessionId: String,
        idempotencyKey: String,
        fast: TranscriptHypothesis,
        risk: VoiceCommandRisk
    ): VoiceExecutionRecord {
        require(sessionId.isNotBlank())
        val existing = records[sessionId]
        if (existing != null) return existing
        val record = VoiceExecutionRecord(
            sessionId = sessionId,
            idempotencyKey = idempotencyKey,
            fastTranscriptHash = sha256(fast.text),
            fastRevision = fast.revision,
            risk = risk,
            updatedAtMillis = clock()
        )
        records[sessionId] = record
        persist()
        return record
    }

    @Synchronized
    fun snapshot(sessionId: String): VoiceExecutionRecord? = records[sessionId]

    @Synchronized
    fun all(): List<VoiceExecutionRecord> = records.values.toList()

    @Synchronized
    fun claimPrimaryDispatch(sessionId: String): Boolean = updateIf(sessionId) { record ->
        if (record.primaryDispatchClaimed) null else record.copy(primaryDispatchClaimed = true)
    }

    @Synchronized
    fun claimExternalSideEffect(sessionId: String): Boolean = updateIf(sessionId) { record ->
        if (record.externalSideEffectCount >= 1) null else record.copy(externalSideEffectCount = 1)
    }

    @Synchronized
    fun claimAgentRun(sessionId: String): Boolean = updateIf(sessionId) { record ->
        if (record.agentRunCount >= 1) null else record.copy(agentRunCount = 1)
    }

    @Synchronized
    fun claimTtsCorrection(sessionId: String): Boolean = updateIf(sessionId) { record ->
        if (record.ttsCorrectionCount >= 1) null else record.copy(ttsCorrectionCount = 1)
    }

    @Synchronized
    fun acceptCorrectionRevision(sessionId: String, revision: Int): Boolean = updateIf(sessionId) { record ->
        if (revision <= record.highestCorrectionRevision) null else {
            record.copy(highestCorrectionRevision = revision)
        }
    }

    @Synchronized
    fun markUserEdited(sessionId: String): Boolean = updateIf(sessionId) { record ->
        if (record.userEdited) null else record.copy(userEdited = true)
    }

    @Synchronized
    fun remove(sessionId: String) {
        if (records.remove(sessionId) != null) persist()
    }

    @Synchronized
    fun clear() {
        if (records.isEmpty()) return
        records.clear()
        persist()
    }

    private fun updateIf(
        sessionId: String,
        transform: (VoiceExecutionRecord) -> VoiceExecutionRecord?
    ): Boolean {
        val current = records[sessionId] ?: return false
        val updated = transform(current)?.copy(updatedAtMillis = clock()) ?: return false
        records[sessionId] = updated
        persist()
        return true
    }

    private fun persist() {
        trim()
        persistence?.save(records.values.toList())
    }

    private fun trim() {
        while (records.size > maxRecords) {
            records.entries.iterator().run {
                if (hasNext()) {
                    next()
                    remove()
                }
            }
        }
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.trim().toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }
}
