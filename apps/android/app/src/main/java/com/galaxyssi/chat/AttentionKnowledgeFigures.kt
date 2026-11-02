package com.galaxyssi.chat

/** An extractive figure view, not a generated explanation or a replacement for the full chapter. */
internal object AttentionKnowledgeFigures {
    fun extract(document: AttentionArticleDocument): AttentionArticleDocument? {
        if (document.cover == null) return null
        val result = mutableListOf<AttentionArticleBlock>()
        var heading: AttentionArticleBlock? = null
        var lastHeading: AttentionArticleBlock? = null
        val blocks = document.blocks
        for ((index, block) in blocks.withIndex()) {
            if (block.kind == "heading") heading = block
            if (block.kind != "image") continue
            if (heading != null && heading != lastHeading) { result += heading; lastHeading = heading }
            result += block
            // A multi-panel figure may have several consecutive images followed by one shared caption.
            val following = blocks.getOrNull(index + 1)
            if (following?.kind == "caption") {
                result += blocks.drop(index + 1).takeWhile { it.kind == "caption" }
            } else if (following?.kind != "image" && block.text.isNotBlank()) {
                result += AttentionArticleBlock("caption", block.text)
            }
        }
        result += blocks.filter { it.kind == "attribution" }
        return AttentionArticleDocument(result)
    }
}
