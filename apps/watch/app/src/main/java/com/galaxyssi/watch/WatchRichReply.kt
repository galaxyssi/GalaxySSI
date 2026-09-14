package com.galaxyssi.watch

import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.text.style.URLSpan
import com.galaxyssi.chat.AgentRichBlock
import com.galaxyssi.chat.AgentRichBlockType as Type
import com.galaxyssi.chat.AgentRichContentCodec
import com.galaxyssi.chat.AgentRichInlineMarkdownRenderer

/** Android's rich format parser, laid out vertically for a narrow, transparent watch transcript. */
internal object WatchRichReply {
    fun blocks(raw: String): List<AgentRichBlock> = AgentRichContentCodec.decode(raw)
        .ifEmpty { AgentRichContentCodec.fromText(raw) }

    fun text(block: AgentRichBlock): String = when (block.type) {
        Type.LIST -> block.rows.joinToString("\n") { row ->
            val marker = when (val value = row.firstOrNull()) {
                "checked" -> "\u2611"
                "unchecked" -> "\u2610"
                "bullet", null -> "\u2022"
                else -> if (value.toIntOrNull() != null) "$value." else "\u2022"
            }
            "$marker ${if (row.size > 1) row.drop(1).joinToString(" ") else row.firstOrNull().orEmpty()}"
        }.ifBlank { block.text }
        Type.TABLE, Type.CHART, Type.KEY_VALUE, Type.TIMELINE -> block.rows.joinToString("\n\n") { row ->
            row.mapIndexed { column, cell ->
                block.columns.getOrNull(column)?.takeIf(String::isNotBlank)?.let { "$it: $cell" } ?: cell
            }.joinToString("\n")
        }.ifBlank { block.text.ifBlank { block.fallbackText } }
        Type.DIVIDER -> "\u2014\u2014\u2014"
        Type.PROGRESS -> "${block.value}/${block.maximum} ${block.text}"
        Type.HTML -> org.jsoup.Jsoup.parse(block.text).text()
        else -> block.text.ifBlank { block.fallbackText }
    }.let { body ->
        listOf(block.title, body).filter(String::isNotBlank).distinct().joinToString("\n")
            .ifBlank { block.uri }
    }

    fun render(raw: String): CharSequence = SpannableStringBuilder().apply {
        blocks(raw).forEach { block ->
            val value = text(block)
            if (value.isBlank()) return@forEach
            if (isNotEmpty()) append("\n\n")
            val start = length
            val code = block.type in setOf(Type.CODE, Type.JSON, Type.DIFF, Type.MERMAID)
            append(if (code) value else AgentRichInlineMarkdownRenderer.render(value))
            fun span(value: Any) = setSpan(value, start, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            when (block.type) {
                Type.HEADING -> { span(StyleSpan(Typeface.BOLD)); span(RelativeSizeSpan(1.08f)) }
                Type.QUOTE -> span(StyleSpan(Typeface.ITALIC))
                else -> if (code) { span(TypefaceSpan("monospace")); span(RelativeSizeSpan(0.9f)) }
            }
            if (block.uri.startsWith("https://") || block.uri.startsWith("http://")) span(URLSpan(block.uri))
        }
    }
}
