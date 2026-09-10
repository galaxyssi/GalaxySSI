package com.galaxyssi.chat

import java.net.URI
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.Link
import org.commonmark.node.Text
import org.commonmark.parser.Parser

internal object AgentImagePresentation {
    private const val DISPLAY_TITLE = "image_display_title"
    private val parser = Parser.builder().build()
    private val imageExtension = Regex("(?i)\\.(png|jpe?g|gif|webp|avif|bmp|heic|svg)$")
    private val actionPrefix = Regex("^(?:\u6253\u5f00|\u4e0b\u8f7d|\u67e5\u770b)(?:\\s*[/\uff0f]\\s*(?:\u6253\u5f00|\u4e0b\u8f7d|\u67e5\u770b))*\\s*")
    private val sizeLabel = Regex("(?i)^\\d+(?:\\.\\d+)?\\s*(?:[KMGT]?i?B|bytes?)$")

    fun annotate(blocks: List<AgentRichBlock>, source: String, chinese: Boolean, fallback: String): List<AgentRichBlock> {
        if (!chinese || blocks.none { it.type == AgentRichBlockType.IMAGE }) return blocks
        val labels = mutableMapOf<String, MutableSet<String>>()
        if (source.contains('[')) parser.parse(source.take(64_000)).accept(object : AbstractVisitor() {
            override fun visit(link: Link) {
                val label = StringBuilder()
                link.accept(object : AbstractVisitor() {
                    override fun visit(text: Text) { label.append(text.literal) }
                })
                val title = label.toString().replace(actionPrefix, "").trim()
                val name = runCatching { URI(link.destination).path?.substringAfterLast('/') }.getOrNull()
                if (!name.isNullOrBlank() && hasChinese(title) && title.length <= 120) {
                    labels.getOrPut(name) { mutableSetOf() }.add(title)
                }
            }
        })
        return blocks.map { block ->
            if (block.type != AgentRichBlockType.IMAGE) block else {
                val original = block.title.trim()
                val title = if (hasChinese(original)) original.replace(imageExtension, "")
                    else labels[original]?.singleOrNull() ?: fallback
                block.copy(metadata = block.metadata + (DISPLAY_TITLE to title))
            }
        }
    }

    fun title(block: AgentRichBlock, fallback: String): String =
        block.metadata[DISPLAY_TITLE].orEmpty().ifBlank { block.title.ifBlank { fallback } }

    fun caption(block: AgentRichBlock): String {
        val text = block.text.trim()
        val parts = text.split('\u00b7').map(String::trim)
        val category = block.metadata["category"].orEmpty()
        val generated = parts.size == 2 && sizeLabel.matches(parts[1]) &&
            (parts[0] == category || parts[0].lowercase() in setOf("outputs", "output", "artifacts", "downloads"))
        return if (generated) "" else block.text
    }

    private fun hasChinese(text: String): Boolean = text.any { it in '\u3400'..'\u9fff' }
}
