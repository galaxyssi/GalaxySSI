package com.galaxyssi.chat.voice.tts

fun interface BargeInElapsedClock {
    fun elapsedRealtimeNanos(): Long
}

enum class BargeInTaskKind {
    ORDINARY_MODEL,
    PERSISTENT_AGENT,
    LOCAL_ACTION,
    NONE
}

data class BargeInActions(
    val stopSpeech: () -> Boolean,
    val cancelOrdinaryModel: () -> Unit,
    val releaseAudioFocus: () -> Unit
)

data class BargeInResult(
    val speechInterrupted: Boolean,
    val ordinaryModelCancelled: Boolean,
    val persistentAgentRetained: Boolean,
    val elapsedMs: Long
)

class BargeInController(
    private val clock: BargeInElapsedClock = BargeInElapsedClock(System::nanoTime)
) {
    fun interrupt(taskKind: BargeInTaskKind, actions: BargeInActions): BargeInResult {
        val startedAt = clock.elapsedRealtimeNanos()
        val interrupted = actions.stopSpeech()
        val cancelModel = taskKind == BargeInTaskKind.ORDINARY_MODEL
        if (cancelModel) actions.cancelOrdinaryModel()
        actions.releaseAudioFocus()
        val elapsed = ((clock.elapsedRealtimeNanos() - startedAt).coerceAtLeast(0L) / 1_000_000L)
        return BargeInResult(
            speechInterrupted = interrupted,
            ordinaryModelCancelled = cancelModel,
            persistentAgentRetained = taskKind == BargeInTaskKind.PERSISTENT_AGENT,
            elapsedMs = elapsed
        )
    }
}
