package com.galaxyssi.chat.voice.asr

import com.galaxyssi.chat.voice.TranscriptHypothesis
import java.security.MessageDigest

enum class TranscriptSource {
    ONLINE_PRIMARY,
    LOCAL_FALLBACK,
    ACCURATE_PASS,
    MANUAL_EDIT
}

sealed interface TranscriptArbitrationDecision {
    data class Commit(
        val hypothesis: TranscriptHypothesis,
        val record: TranscriptCommitRecord
    ) : TranscriptArbitrationDecision

    data class Correction(val hypothesis: TranscriptHypothesis) : TranscriptArbitrationDecision
    data class DisplayOnly(val hypothesis: TranscriptHypothesis) : TranscriptArbitrationDecision
    data class Ignored(val reasonCode: String) : TranscriptArbitrationDecision
}

data class TranscriptCommitRecord(
    val transcriptId: String,
    val committedRevision: Long,
    val committedTextHash: String,
    val providerId: String,
    val modelProfileId: String?,
    val committedAtElapsedNs: Long,
    val executionId: String? = null,
    val userConfirmed: Boolean = false
)

class FinalTranscriptArbiter(
    private val elapsedNanos: () -> Long = System::nanoTime
) {
    private data class State(
        var highestRevision: Long = -1L,
        var record: TranscriptCommitRecord? = null,
        var latestTextHash: String = ""
    )

    private val lock = Any()
    private val states = linkedMapOf<String, State>()

    fun consider(
        hypothesis: TranscriptHypothesis,
        source: TranscriptSource,
        executionId: String? = null,
        userConfirmed: Boolean = false
    ): TranscriptArbitrationDecision = synchronized(lock) {
        val transcriptId = hypothesis.transcriptId.trim()
        if (transcriptId.isBlank()) return@synchronized TranscriptArbitrationDecision.Ignored("missing_transcript_id")
        val normalized = hypothesis.text.trim()
        if (normalized.isBlank()) return@synchronized TranscriptArbitrationDecision.Ignored("empty_transcript")
        val revision = hypothesis.revision.toLong()
        val state = states.getOrPut(transcriptId) { State() }
        val hash = hash(normalized)
        if (revision < state.highestRevision && source != TranscriptSource.MANUAL_EDIT) {
            return@synchronized TranscriptArbitrationDecision.Ignored("stale_revision")
        }
        state.highestRevision = maxOf(state.highestRevision, revision)

        if (!hypothesis.isFinal && source != TranscriptSource.MANUAL_EDIT) {
            if (hash == state.latestTextHash) return@synchronized TranscriptArbitrationDecision.Ignored("duplicate_partial")
            state.latestTextHash = hash
            return@synchronized TranscriptArbitrationDecision.DisplayOnly(hypothesis)
        }

        val committed = state.record
        if (committed == null) {
            if (source == TranscriptSource.ACCURATE_PASS) {
                return@synchronized TranscriptArbitrationDecision.Correction(hypothesis)
            }
            val record = TranscriptCommitRecord(
                transcriptId = transcriptId,
                committedRevision = revision,
                committedTextHash = hash,
                providerId = hypothesis.providerId,
                modelProfileId = hypothesis.modelProfileId.takeIf(String::isNotBlank),
                committedAtElapsedNs = elapsedNanos().coerceAtLeast(0L),
                executionId = executionId,
                userConfirmed = userConfirmed || source == TranscriptSource.MANUAL_EDIT
            )
            state.record = record
            state.latestTextHash = hash
            return@synchronized TranscriptArbitrationDecision.Commit(hypothesis, record)
        }

        if (hash == committed.committedTextHash) {
            return@synchronized TranscriptArbitrationDecision.Ignored("duplicate_final")
        }
        if (committed.userConfirmed && source != TranscriptSource.MANUAL_EDIT) {
            return@synchronized TranscriptArbitrationDecision.Ignored("confirmed_final_locked")
        }
        if (source == TranscriptSource.MANUAL_EDIT || source == TranscriptSource.ACCURATE_PASS) {
            return@synchronized TranscriptArbitrationDecision.Correction(hypothesis)
        }
        TranscriptArbitrationDecision.Ignored("execution_already_committed")
    }

    fun committed(transcriptId: String): TranscriptCommitRecord? = synchronized(lock) {
        states[transcriptId]?.record
    }

    fun clear(transcriptId: String) {
        synchronized(lock) { states.remove(transcriptId) }
    }

    fun clearAll() {
        synchronized(lock) { states.clear() }
    }

    private fun hash(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }
}
