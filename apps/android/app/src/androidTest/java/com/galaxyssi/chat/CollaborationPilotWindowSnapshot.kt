package com.galaxyssi.chat

import android.content.Context

/** Observe persisted window selection, not the legacy store's changing first-active fallback. */
internal object CollaborationPilotWindowSnapshot {
    fun read(context: Context): Map<String, String> {
        val state = AgentEncryptedDatabase(context.applicationContext, "agent_window_state_v1")
        return synchronized(AgentTranscriptWindowMutationLock) {
            state.keys().filter { it.startsWith("selected:") }
                .associateWith { state.readString(it, "") }
        }
    }
}
