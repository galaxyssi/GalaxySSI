package com.galaxyssi.chat

import com.galaxyssi.chat.voice.VoiceConversationSession

/** Automatic speech belongs to the newest utterance, not the newest screen update. */
internal class AgentVoiceReplySpeech(private val session: VoiceConversationSession) {
    val controller = AgentReplySpeechController(sessionPrefix = "voice-call")

    fun observe(entries: List<AgentTranscriptEntry>): AgentReplySpeechCommand {
        if (!session.active || session.muted || session.latestTurnId.isBlank()) return controller.stop()
        val target = entries.asReversed().asSequence()
            .filter { it.turnId == session.latestTurnId && session.acceptsTurn(it.conversationId, it.turnId) }
            .mapNotNull { AgentReplySpeechPresentationPolicy.target(it, allowEmptyFinal = true) }
            .firstOrNull() ?: return AgentReplySpeechCommand()
        if (target.text.isBlank()) {
            // A canonical visual-only final closes prior speech or completes silently.
            if (controller.isEnabled(target)) return controller.observe(target)
            return AgentReplySpeechCommand(completedWithoutPlayback =
                session.claimSpeech(session.conversationId, session.latestTurnId))
        }
        return when {
            session.claimSpeech(session.conversationId, session.latestTurnId) -> controller.toggle(target)
            controller.isEnabled(target) -> controller.observe(target)
            else -> AgentReplySpeechCommand()
        }
    }
}
