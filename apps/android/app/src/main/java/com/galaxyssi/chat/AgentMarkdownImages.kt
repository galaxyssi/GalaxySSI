package com.galaxyssi.chat

import java.net.URI
import java.util.UUID
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.Image
import org.commonmark.node.Text
import org.commonmark.parser.IncludeSourceSpans
import org.commonmark.parser.Parser

internal object AgentMarkdownImages {
    const val SOURCE = "markdown_image_source"
    private val parser = Parser.builder().includeSourceSpans(IncludeSourceSpans.BLOCKS_AND_INLINES).build()

    fun split(text: String): List<AgentRichBlock> {
        val images = mutableListOf<Image>()
        if (text.contains("![")) parser.parse(text).accept(object : AbstractVisitor() {
            override fun visit(image: Image) {
                if (isWebSource(image.destination) && image.sourceSpans.isNotEmpty()) images += image
            }
        })
        if (images.isEmpty()) return listOf(textBlock(text))
        val result = mutableListOf<AgentRichBlock>()
        var cursor = 0
        images.take(32).forEach { image ->
            val start = image.sourceSpans.first().inputIndex
            val end = image.sourceSpans.last().let { it.inputIndex + it.length }
            if (start < cursor || end > text.length) return@forEach
            if (start > cursor) text.substring(cursor, start).trim().takeIf(String::isNotBlank)
                ?.let { result += textBlock(it) }
            val alt = StringBuilder()
            image.accept(object : AbstractVisitor() {
                override fun visit(text: Text) { alt.append(text.literal) }
            })
            result += AgentRichBlock(
                id = UUID.randomUUID().toString(), type = AgentRichBlockType.IMAGE,
                title = alt.toString().ifBlank { image.title.orEmpty() }.take(500),
                uri = image.destination, metadata = mapOf(SOURCE to image.destination)
            )
            cursor = end
        }
        text.substring(cursor).trim().takeIf(String::isNotBlank)?.let { result += textBlock(it) }
        return result
    }

    fun isWebSource(value: String): Boolean = runCatching {
        val uri = URI(value)
        value.length <= 4096 && uri.scheme?.lowercase() in setOf("https", "http") &&
            !uri.host.isNullOrBlank() && uri.rawUserInfo == null
    }.getOrDefault(false)

    private fun textBlock(text: String) = AgentRichBlock(
        UUID.randomUUID().toString(), AgentRichBlockType.TEXT, text = text
    )
}
