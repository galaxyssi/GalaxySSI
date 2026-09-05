package com.galaxyssi.chat

import android.widget.Toast
import com.galaxyssi.chat.voice.agent.VoiceAgentRunSnapshot

internal fun MainActivity.loadVoiceRunForAction(
    reference: AgentVoiceRunReference,
    action: (VoiceAgentRunSnapshot) -> Unit
) {
    if (!isVoiceAgentRunBridgeInitialized()) return
    agentTranscriptContentExecutor.execute {
        if (isFinishing || isDestroyed) return@execute
        val snapshot = runCatching {
            voiceAgentRunBridge.find(reference.runId)?.takeIf { run ->
                val conversationId = agentTranscriptStore.resolveMergedConversationId(run.conversationId)
                    ?: run.conversationId
                run.runId == reference.runId && reference.matches(conversationId, run.turnId, run.taskId)
            }
        }.getOrNull()
        runOnUiThread {
            if (isFinishing || isDestroyed) return@runOnUiThread
            if (snapshot != null) action(snapshot)
            else Toast.makeText(this, R.string.agent_task_detail_unavailable, Toast.LENGTH_SHORT).show()
        }
    }
}
