package com.galaxyssi.chat

import java.net.URI
import java.util.UUID
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.Image
import org.commonmark.node.Link
import org.commonmark.node.Node
import org.commonmark.node.Text
import org.commonmark.parser.IncludeSourceSpans
import org.commonmark.parser.Parser

internal object AgentMarkdownImages {
    const val SOURCE = "markdown_image_source"
    private val parser = Parser.builder().includeSourceSpans(IncludeSourceSpans.BLOCKS_AND_INLINES).build()

    fun withoutInternalArtifactLinks(text: String): String {
        if (!text.contains("galaxyssi-artifact://", ignoreCase = true)) return text
        val spans = mutableListOf<Pair<Int, Int>>()
        fun collect(node: Node, destination: String) {
            if (!destination.startsWith("galaxyssi-artifact://", ignoreCase = true)) return
            val source = node.sourceSpans
            if (source.isNotEmpty()) {
                spans += source.first().inputIndex to source.last().let { it.inputIndex + it.length }
            }
        }
        parser.parse(text).accept(object : AbstractVisitor() {
            override fun visit(image: Image) = collect(image, image.destination)
            override fun visit(link: Link) {
                collect(link, link.destination)
                super.visit(link)
            }
        })
        var cursor = 0
        return buildString {
            spans.sortedBy { it.first }.forEach { (start, end) ->
                if (start >= cursor && end <= text.length) {
                    append(text, cursor, start)
                    cursor = end
                }
            }
            append(text, cursor, text.length)
        }
    }

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
