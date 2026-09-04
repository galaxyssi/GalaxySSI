package com.galaxyssi.chat.voice.tts

data class ProgressiveTtsUtteranceRequest(
    val utteranceId: String,
    val sessionId: String,
    val onStarted: () -> Unit,
    val onFinished: (success: Boolean) -> Unit
)

class ProgressiveTtsUtteranceRegistry {
    private var active: ProgressiveTtsUtteranceRequest? = null

    @Synchronized
    fun begin(request: ProgressiveTtsUtteranceRequest) {
        active = request
    }

    @Synchronized
    fun started(utteranceId: String?): ProgressiveTtsUtteranceRequest? {
        val current = active ?: return null
        return current.takeIf { utteranceId?.isNotBlank() == true && it.utteranceId == utteranceId }
    }

    @Synchronized
    fun finish(utteranceId: String?): ProgressiveTtsUtteranceRequest? {
        val current = started(utteranceId) ?: return null
        active = null
        return current
    }

    @Synchronized
    fun clear(): ProgressiveTtsUtteranceRequest? = active.also { active = null }
}
