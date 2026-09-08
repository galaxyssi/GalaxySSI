package com.galaxyssi.chat.voice

/** Owns a voice call independently of any one ASR utterance or durable agent task. */
class VoiceConversationSession {
    var generation: Long = 0
        private set
    var conversationId: String = ""
        private set
    var active: Boolean = false
        private set
    var expanded: Boolean = false
        private set
    var muted: Boolean = false
        private set
    private val traces = linkedMapOf<String, Long>()
    private val turns = linkedMapOf<String, Long>()
    private val turnTraces = linkedMapOf<String, String>()
    private val spokenTurns = mutableSetOf<String>()
    private var mediaSequence = 0L
    private var mediaPlaybackId: Long? = null
    private var resumeAfterMedia = false
    var latestTurnId = ""
        private set
    var latestTraceId = ""
        private set

    fun begin(conversationId: String): Long {
        require(conversationId.isNotBlank())
        generation++
        this.conversationId = conversationId
        active = true
        expanded = true
        muted = false
        clearMediaPlayback()
        spokenTurns.clear()
        latestTurnId = ""
        latestTraceId = ""
        return generation
    }

    fun end() {
        generation++
        active = false
        expanded = false
        muted = false
        clearMediaPlayback()
    }

    fun expand(value: Boolean) { expanded = active && value }
    fun mute(value: Boolean) {
        clearMediaPlayback()
        muted = active && value
    }

    fun beginMediaPlayback(): Long? {
        if (!active) return null
        // A replacement video inherits the original intent, not the temporary mute.
        if (mediaPlaybackId == null) resumeAfterMedia = !muted
        muted = true
        cancelPendingInput()
        return (++mediaSequence).also { mediaPlaybackId = it }
    }

    fun finishMediaPlayback(id: Long): Boolean {
        if (!active || mediaPlaybackId != id) return false
        val shouldResume = resumeAfterMedia
        clearMediaPlayback()
        return shouldResume
    }

    fun cancelMediaPlayback(id: Long) {
        if (mediaPlaybackId == id) clearMediaPlayback()
    }

    private fun clearMediaPlayback() {
        mediaPlaybackId = null
        resumeAfterMedia = false
    }

    fun cancelPendingInput() {
        traces.keys.toList().forEach { traces[it] = -1 }
    }

    fun isCurrent(token: Long, conversationId: String = this.conversationId): Boolean =
        active && generation == token && this.conversationId == conversationId

    fun registerTrace(traceId: String) {
        if (!active || traceId.isBlank()) return
        if (traces[traceId] != generation) latestTurnId = ""
        traces[traceId] = generation
        latestTraceId = traceId
        trim(traces)
    }

    fun ownsTrace(traceId: String): Boolean = traceId.isNotBlank() && traces.containsKey(traceId)

    fun acceptsTrace(traceId: String): Boolean =
        active && !muted && traceId == latestTraceId && traces[traceId] == generation

    fun registerTurn(traceId: String, turnId: String) {
        if (!acceptsTrace(traceId) || turnId.isBlank()) return
        turns[turnId] = generation
        turnTraces[turnId] = traceId
        latestTurnId = turnId
        trim(turns)
        turnTraces.keys.retainAll(turns.keys)
        spokenTurns.retainAll(turns.keys)
    }

    fun acceptsTurn(conversationId: String, turnId: String): Boolean =
        active && this.conversationId == conversationId && turns[turnId] == generation

    fun claimSpeech(conversationId: String, turnId: String): Boolean =
        !muted && turnId == latestTurnId && acceptsTurn(conversationId, turnId) && spokenTurns.add(turnId)

    fun traceForTurn(turnId: String): String =
        turnTraces[turnId].orEmpty().takeIf { acceptsTurn(conversationId, turnId) }.orEmpty()

    private fun trim(entries: LinkedHashMap<String, Long>) {
        while (entries.size > 64) entries.remove(entries.keys.first())
    }
}
