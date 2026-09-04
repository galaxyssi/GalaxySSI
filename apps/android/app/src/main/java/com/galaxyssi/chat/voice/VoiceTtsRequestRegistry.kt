package com.galaxyssi.chat.voice

internal data class VoiceTtsRequest(
    val utteranceId: String,
    val traceId: String,
    val onFinished: () -> Unit
)

internal class VoiceTtsRequestRegistry {
    private var active: VoiceTtsRequest? = null

    @Synchronized
    fun begin(request: VoiceTtsRequest) {
        active = request
    }

    @Synchronized
    fun finish(utteranceId: String?): VoiceTtsRequest? {
        val current = active ?: return null
        if (utteranceId.isNullOrBlank() || current.utteranceId != utteranceId) return null
        active = null
        return current
    }

    @Synchronized
    fun discard(utteranceId: String?): Boolean {
        val current = active ?: return false
        if (utteranceId.isNullOrBlank() || current.utteranceId != utteranceId) return false
        active = null
        return true
    }

    @Synchronized
    fun clear() {
        active = null
    }
}
