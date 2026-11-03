package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.os.Looper
import android.widget.Toast
import java.lang.ref.WeakReference
import java.util.UUID

internal data class VoiceReplyPlaybackState(
    val requestId: String = "",
    val selection: VoiceReplySelection? = null,
    val status: String = "stopped"
) {
    val playing get() = status == "loading" || status == "playing"
}

/** No reply text, audio, Activity or persisted auto-play flag is retained here. */
internal object VoiceReplyPlayback {
    var state = VoiceReplyPlaybackState()
        private set
    private val windows = mutableListOf<WeakReference<MainActivity>>()

    fun watch(activity: MainActivity) {
        windows.removeAll { it.get() == null }
        if (windows.none { it.get() === activity }) windows += WeakReference(activity)
    }

    fun publish(value: VoiceReplyPlaybackState) {
        check(Looper.myLooper() == Looper.getMainLooper())
        val previous = state
        if (previous == value) return
        state = value
        val changed = listOfNotNull(previous.selection?.entryId, value.selection?.entryId)
        windows.removeAll { it.get() == null || it.get()?.isDestroyed == true }
        windows.mapNotNull { it.get() }.filter { it.hasWindowFocus() && !it.runtimePlaintextCleared }
            .forEach {
                it.notifyAgentReplySpeechRows(changed)
                if (value.status == "failed" && previous.status != "failed") {
                    Toast.makeText(it, R.string.agent_reply_speech_failed, Toast.LENGTH_SHORT).show()
                }
            }
    }

    fun start(context: Context, selection: VoiceReplySelection): Boolean {
        val request = UUID.randomUUID().toString()
        publish(VoiceReplyPlaybackState(request, selection, "loading"))
        return try {
            context.startForegroundService(Intent(context, VoiceNewsPlaybackService::class.java).setAction("reply")
                .putExtra("reply_request", request).putExtra("reply_conversation", selection.conversationId)
                .putExtra("reply_entry", selection.entryId).putExtra("reply_offset", selection.offset))
            true
        } catch (_: Exception) {
            publish(VoiceReplyPlaybackState(request, selection, "failed")); false
        }
    }

    fun stop(): Boolean {
        if (state.selection == null || state.status == "stopped") return false
        publish(VoiceReplyPlaybackState())
        VoiceNewsPlaybackService.stopReply()
        return true
    }
}
