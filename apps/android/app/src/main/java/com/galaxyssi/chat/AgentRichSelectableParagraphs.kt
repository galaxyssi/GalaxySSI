package com.galaxyssi.chat

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.method.LinkMovementMethod
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.widget.TextView
import com.galaxyssi.chat.ui.ParagraphSelectingTextView

internal object AgentRichSelectableParagraphs {
    private val supportedTypes = setOf(
        AgentRichBlockType.TEXT,
        AgentRichBlockType.HEADING,
        AgentRichBlockType.QUOTE,
        AgentRichBlockType.LIST,
        AgentRichBlockType.DIVIDER
    )

    fun supports(block: AgentRichBlock): Boolean = block.type in supportedTypes

    fun createView(
        context: Context,
        blocks: List<AgentRichBlock>,
        inlineMarkdown: (String) -> CharSequence,
        lineSpacingExtraPx: Float,
        onTextViewReady: (TextView) -> Unit
    ): TextView = ParagraphSelectingTextView(context).apply {
        text = buildText(blocks, inlineMarkdown)
        textSize = 16f
        includeFontPadding = false
        setTextColor(Color.parseColor("#14202B"))
        setLinkTextColor(Color.parseColor("#087F69"))
        setLineSpacing(lineSpacingExtraPx, 1f)
        movementMethod = LinkMovementMethod.getInstance()
        onTextViewReady(this)
    }

    private fun buildText(
        blocks: List<AgentRichBlock>,
        inlineMarkdown: (String) -> CharSequence
    ): CharSequence = SpannableStringBuilder().apply {
        blocks.forEach { block ->
            if (isNotEmpty() && last() != '\n') append("\n\n")
            val start = length
            appendBlock(block, inlineMarkdown)
            styleBlock(block, start, length)
        }
    }

    private fun SpannableStringBuilder.appendBlock(
        block: AgentRichBlock,
        inlineMarkdown: (String) -> CharSequence
    ) {
        when (block.type) {
            AgentRichBlockType.TEXT -> append(inlineMarkdown(block.text))
            AgentRichBlockType.HEADING -> append(inlineMarkdown(block.text.ifBlank { block.title }))
            AgentRichBlockType.QUOTE -> append(inlineMarkdown(block.text))
            AgentRichBlockType.LIST -> block.rows.forEachIndexed { index, row ->
                if (index > 0) append('\n')
                append(listMarker(row.firstOrNull().orEmpty()))
                append(inlineMarkdown(row.getOrNull(1).orEmpty()))
            }
            AgentRichBlockType.DIVIDER -> append("\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500")
            else -> Unit
        }
    }

    private fun SpannableStringBuilder.styleBlock(block: AgentRichBlock, start: Int, end: Int) {
        when (block.type) {
            AgentRichBlockType.HEADING -> {
                setSpan(StyleSpan(Typeface.BOLD), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                setSpan(
                    RelativeSizeSpan(if (block.metadata["level"] == "1") 1.25f else 1.12f),
                    start,
                    end,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            AgentRichBlockType.QUOTE -> setSpan(
                ForegroundColorSpan(Color.parseColor("#5F6368")),
                start,
                end,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            AgentRichBlockType.DIVIDER -> setSpan(
                ForegroundColorSpan(Color.parseColor("#C8CDD2")),
                start,
                end,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            else -> Unit
        }
    }

    private fun listMarker(marker: String): String = when (marker) {
        "checked" -> "\u2713 "
        "unchecked" -> "\u25CB "
        "bullet" -> "\u2022 "
        else -> "$marker. "
    }
}
