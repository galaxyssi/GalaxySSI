package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup

internal object ConversationScheduleCardPresentation {
    fun isCard(block: AgentRichBlock): Boolean = block.type == AgentRichBlockType.ACTIONS &&
        block.actions.singleOrNull()?.verb == "edit_scheduled_task"

    fun visibleBlocks(blocks: List<AgentRichBlock>): List<AgentRichBlock> =
        if (blocks.any(::isCard)) blocks.filterNot { it.type == AgentRichBlockType.TEXT } else blocks

    // Older cards stored execution diagnostics after the frequency on separate lines.
    fun compactDetail(block: AgentRichBlock): String = block.text.lineSequence().firstOrNull().orEmpty()

    fun speechText(title: String, detail: String): String =
        listOf(title, detail).filter(String::isNotBlank).joinToString("\n")

    fun speechText(blocks: List<AgentRichBlock>): String? = blocks.filter(::isCard)
        .takeIf { it.isNotEmpty() }
        ?.joinToString("\n\n") { speechText(it.title, compactDetail(it)) }

    /** Read the already-rendered status; no database query or stale transcript snapshot. */
    fun visibleSpeechText(content: View?): String? {
        val texts = mutableListOf<String>()
        fun visit(view: View) {
            if (view.visibility != View.VISIBLE) return
            if (view is ConversationScheduleStatusView) view.cardSpeechText()?.let(texts::add)
            if (view is ViewGroup) for (index in 0 until view.childCount) visit(view.getChildAt(index))
        }
        content?.let(::visit)
        return texts.takeIf { it.isNotEmpty() }?.joinToString("\n\n")
    }
}
