package com.galaxyssi.chat

internal object AgentRichContentUpdatePolicy {
    fun supports(blocks: List<AgentRichBlock>): Boolean = blocks.all {
        AgentRichSelectableParagraphs.supports(it) || it.type in setOf(
            AgentRichBlockType.IMAGE, AgentRichBlockType.TABLE, AgentRichBlockType.CODE,
            AgentRichBlockType.JSON, AgentRichBlockType.KEY_VALUE)
    }

    fun groups(blocks: List<AgentRichBlock>): List<List<AgentRichBlock>> = buildList {
        var start = 0
        while (start < blocks.size) {
            var end = start + 1
            if (AgentRichSelectableParagraphs.supports(blocks[start])) {
                while (end < blocks.size && AgentRichSelectableParagraphs.supports(blocks[end])) end++
            }
            add(blocks.subList(start, end).toList())
            start = end
        }
    }

    // Markdown parsing assigns fresh IDs; passive block content determines whether its View changed.
    fun sameContent(previous: List<AgentRichBlock>, current: List<AgentRichBlock>): Boolean =
        previous.size == current.size && previous.indices.all { index ->
            previous[index].copy(id = "") == current[index].copy(id = "")
        }
}
