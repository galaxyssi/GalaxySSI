package com.galaxyssi.chat

import android.view.ViewGroup
import android.view.View
import android.widget.LinearLayout

/** Retains reply content while stream, speech and terminal metadata change. */
internal class AgentStableAssistantRow(
    private val activity: MainActivity,
    private var entry: AgentTranscriptEntry
) : LinearLayout(activity) {
    private val content = activity.agentAssistantRichContent(entry, entry)
    private val footer = LinearLayout(activity).apply { orientation = VERTICAL }
    private var speechFooter: View? = null
    private var executionFooter: View? = null

    init {
        orientation = VERTICAL
        layoutParams = LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        addView(content)
        addView(footer, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        refreshFooter()
    }

    fun bind(next: AgentTranscriptEntry): Boolean {
        if (!supports(next) || !AgentTranscriptRenderPolicy.sameItem(entry, next) ||
            !activity.updateAgentAssistantRichContent(content, next)) return false
        entry = next
        refreshFooter()
        return true
    }

    private fun refreshFooter() {
        val speech = activity.agentReplySpeechFooter(entry, speechFooter)
        if (speech !== speechFooter) {
            speechFooter?.let(footer::removeView)
            speech?.let { footer.addView(it, 0) }
            speechFooter = speech
        }
        val execution = activity.agentAssistantExecutionLabel(entry, executionFooter)
        if (execution !== executionFooter) {
            executionFooter?.let(footer::removeView)
            execution?.let(footer::addView)
            executionFooter = execution
        }
    }

    companion object {
        fun supports(entry: AgentTranscriptEntry): Boolean =
            entry.role == AgentTranscriptRole.ASSISTANT && entry.sourceConversationId.isBlank() &&
                !AgentReplyWaitingIndicatorPolicy.isIndicator(entry) &&
                entry.textChunkCount == 0 && entry.richOutputChunkCount == 0 &&
                !AgentLargeOutputPolicy.hasDeferredContent(entry)
    }
}
