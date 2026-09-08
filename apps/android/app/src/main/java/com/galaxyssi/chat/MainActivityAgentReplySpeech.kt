package com.galaxyssi.chat

import android.view.Gravity
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.Toast
import androidx.recyclerview.widget.RecyclerView
import com.galaxyssi.chat.ui.AgentReplySpeechButton
import com.galaxyssi.chat.ui.ParagraphSelectingTextView
import com.galaxyssi.chat.voice.tts.TtsCancelReason
import com.galaxyssi.chat.voice.tts.TtsChunkSchedulerCallbacks
import java.util.WeakHashMap

private object AgentReplySpeechRuntime {
    private val controllers = WeakHashMap<MainActivity, AgentReplySpeechController>()

    @Synchronized
    fun controller(activity: MainActivity): AgentReplySpeechController =
        controllers.getOrPut(activity) { AgentReplySpeechController() }
}

internal fun MainActivity.observeAgentReplySpeech(
    entries: List<AgentTranscriptEntry>
): Set<String> {
    agentVoiceConversation?.onEntries(entries)
    return applyAgentReplySpeechCommand(
        AgentReplySpeechRuntime.controller(this).observe(
            AgentReplySpeechPresentationPolicy.latestTarget(entries)
        )
    )
}

internal fun MainActivity.decorateAgentReplySpeech(
    entry: AgentTranscriptEntry,
    content: View
): View {
    val target = AgentReplySpeechPresentationPolicy.target(entry) ?: return content
    val controller = AgentReplySpeechRuntime.controller(this)
    val latest = AgentReplySpeechPresentationPolicy.latestTarget(renderedAgentTranscriptSourceEntries)
    if (latest?.responseId != target.responseId && !controller.isActive(target)) return content

    val button = AgentReplySpeechButton(this).apply {
        tag = "agent-reply-speech:${target.responseId}"
        setPlaying(controller.isEnabled(target))
        setOnClickListener {
            val command = controller.toggle(target)
            setPlaying(controller.isEnabled(target))
            notifyAgentReplySpeechRows(command.changedEntryIds - entry.id)
            val changed = applyAgentReplySpeechCommand(command)
            setPlaying(controller.isEnabled(target))
            notifyAgentReplySpeechRows(changed - entry.id)
        }
    }
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        addView(content)
        addView(
            LinearLayout(this@decorateAgentReplySpeech).apply {
                gravity = Gravity.END
                addView(
                    button,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        dp(32)
                    )
                )
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(1) }
        )
    }
}

internal fun MainActivity.attachAgentReplyParagraphSpeech(
    textView: android.widget.TextView,
    entry: AgentTranscriptEntry
) {
    val paragraphView = textView as? ParagraphSelectingTextView ?: return
    paragraphView.setOnParagraphDoubleTapListener { selection ->
        val target = AgentReplySpeechPresentationPolicy.target(entry) ?: return@setOnParagraphDoubleTapListener
        val command = AgentReplySpeechRuntime.controller(this).readFromParagraph(
            target = target,
            paragraph = selection.paragraph,
            sourceText = selection.sourceText,
            startOffset = selection.startOffset
        )
        notifyAgentReplySpeechRows(command.changedEntryIds)
        notifyAgentReplySpeechRows(applyAgentReplySpeechCommand(command))
    }
}

internal fun MainActivity.attachAgentReplySpeechStopGesture() {
    var stopTriggered = false
    val detector = GestureDetector(
        this,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent): Boolean = true

            override fun onDoubleTap(event: MotionEvent): Boolean {
                stopTriggered = stopAgentReplySpeechFromOutput()
                return stopTriggered
            }
        }
    )
    agentOutputList.addOnItemTouchListener(object : RecyclerView.SimpleOnItemTouchListener() {
        override fun onInterceptTouchEvent(
            recyclerView: RecyclerView,
            event: MotionEvent
        ): Boolean {
            if (event.actionMasked == MotionEvent.ACTION_DOWN) stopTriggered = false
            detector.onTouchEvent(event)
            return stopTriggered.also { intercepted ->
                if (intercepted) stopTriggered = false
            }
        }
    })
}

private fun MainActivity.stopAgentReplySpeechFromOutput(): Boolean {
    val controller = AgentReplySpeechRuntime.controller(this)
    if (!controller.isPlaying()) return false
    val command = controller.stop()
    notifyAgentReplySpeechRows(command.changedEntryIds)
    notifyAgentReplySpeechRows(applyAgentReplySpeechCommand(command))
    return true
}

internal fun MainActivity.notifyAgentReplySpeechRows(entryIds: Collection<String>) {
    if (!isAgentTranscriptAdapterInitialized()) return
    entryIds.distinct().forEach { entryId ->
        agentTranscriptAdapter.indexOfEntry(entryId)
            .takeIf { it >= 0 }
            ?.let(agentTranscriptAdapter::notifyItemChanged)
    }
}

internal fun MainActivity.applyAgentReplySpeechCommand(
    command: AgentReplySpeechCommand,
    controller: AgentReplySpeechController = AgentReplySpeechRuntime.controller(this),
    traceId: String = "",
    callbacks: TtsChunkSchedulerCallbacks? = null
): Set<String> {
    if (command.cancelSessionId.isNotBlank() &&
        progressiveTtsScheduler.snapshot().sessionId == command.cancelSessionId
    ) {
        progressiveTtsScheduler.cancel(command.cancelSessionId, TtsCancelReason.USER_STOP)
    }
    if (command.beginSessionId.isNotBlank()) {
        val sessionId = command.beginSessionId
        progressiveTtsScheduler.begin(
            sessionId,
            TtsChunkSchedulerCallbacks(
                onPlaybackStarted = { chunk ->
                    runOnUiThread {
                        if (activeProgressiveSpeechSessionId == sessionId) {
                            voiceAssistantSpeaking = true
                            callbacks?.onPlaybackStarted?.invoke(chunk)
                        }
                    }
                },
                onUnderrun = { count ->
                    runOnUiThread {
                        if (activeProgressiveSpeechSessionId == sessionId) callbacks?.onUnderrun?.invoke(count)
                    }
                },
                onFinished = { success, errorCode ->
                    runOnUiThread {
                        agentReplySpeechFeeder.clear(sessionId)
                        val ownsPlayback = activeProgressiveSpeechSessionId == sessionId
                        if (ownsPlayback) {
                            activeProgressiveSpeechSessionId = ""
                            activeProgressiveSpeechTraceId = ""
                            activeProgressiveSpeechProvider = ""
                            voiceAssistantSpeaking = false
                            releaseVoicePlaybackAudioFocus()
                        }
                        val changed = controller.disable(sessionId)
                        notifyAgentReplySpeechRows(changed)
                        if (ownsPlayback && callbacks != null) callbacks.onFinished(success, errorCode)
                        if (ownsPlayback && !success && callbacks == null) {
                            Toast.makeText(
                                this,
                                R.string.agent_reply_speech_failed,
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                    }
                },
                onCancelled = { reason ->
                    runOnUiThread {
                        agentReplySpeechFeeder.clear(sessionId)
                        val ownsPlayback = activeProgressiveSpeechSessionId == sessionId
                        if (ownsPlayback) {
                            activeProgressiveSpeechSessionId = ""
                            activeProgressiveSpeechTraceId = ""
                            activeProgressiveSpeechProvider = ""
                            voiceAssistantSpeaking = false
                            releaseVoicePlaybackAudioFocus()
                        }
                        val changed = controller.disable(sessionId)
                        notifyAgentReplySpeechRows(changed)
                        if (ownsPlayback) callbacks?.onCancelled?.invoke(reason)
                    }
                },
                onCapacityAvailable = {
                    runOnUiThread {
                        if (activeProgressiveSpeechSessionId == sessionId) {
                            agentReplySpeechFeeder.onCapacityAvailable(sessionId)
                        }
                    }
                }
            )
        )
        activeProgressiveSpeechSessionId = sessionId
        activeProgressiveSpeechTraceId = traceId
        activeProgressiveSpeechProvider = VoiceAssistantSettings.get(this).ttsProvider
        agentReplySpeechFeeder.begin(sessionId)
    }
    if (command.chunks.isNotEmpty()) {
        agentReplySpeechFeeder.offer(command.chunks.first().requestId, command.chunks)
    }
    if (command.finishSessionId.isNotBlank()) {
        agentReplySpeechFeeder.finish(command.finishSessionId)
    }
    if (command.scheduleCommitSessionId.isNotBlank()) {
        val sessionId = command.scheduleCommitSessionId
        handler.postDelayed(
            {
                val due = controller.commitDue(sessionId)
                applyAgentReplySpeechCommand(due, controller, traceId, callbacks)
            },
            AGENT_REPLY_SPEECH_COMMIT_DELAY_MILLIS
        )
    }
    return command.changedEntryIds
}

private const val AGENT_REPLY_SPEECH_COMMIT_DELAY_MILLIS = 525L
