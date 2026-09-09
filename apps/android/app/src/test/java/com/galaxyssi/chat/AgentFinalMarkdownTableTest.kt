package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentFinalMarkdownTableTest {
    private val markdown = "Before\n\n| Month | Fruit |\n| --- | --- |\n| January | Orange |\n| February | Pear |\n\nAfter"

    private fun wrapped(text: String, type: AgentRichBlockType = AgentRichBlockType.TEXT): String =
        AgentRichContentCodec.encode(listOf(AgentRichBlock(
            id = "desktop-final", type = type, text = text, metadata = mapOf("source" to "desktop")
        )))

    private fun signature(blocks: List<AgentRichBlock>) = blocks.map {
        listOf(it.type, it.text, it.columns, it.rows, it.language)
    }

    @Test fun finalReplyMatchesStreamingTableAndSurroundingText() {
        val streamed = AgentRichContentCodec.fromText(markdown)
        val final = AgentRichContentCodec.decode(wrapped(markdown))
        assertEquals(signature(streamed), signature(final))
        assertEquals(2, final.single { it.type == AgentRichBlockType.TABLE }.rows.size)
        assertTrue(final.all { it.metadata["source"] == "desktop" })
    }

    @Test fun persistedReplyAndRepeatedNormalizationKeepTableAndStableIds() {
        val initial = AgentRichContentCodec.decode(wrapped(markdown))
        var encoded = wrapped(markdown)
        repeat(4) { encoded = AgentRichContentCodec.normalize(encoded) }
        assertEquals(initial, AgentRichContentCodec.decode(encoded))
        assertEquals(initial, AgentRichContentCodec.decode(wrapped(markdown)))
    }

    @Test fun fencedTableExampleRemainsCodeWhenRealTableIsPresent() {
        val source = "$markdown\n\n```text\n| Example | Value |\n| --- | --- |\n| A | B |\n```"
        val blocks = AgentRichContentCodec.decode(wrapped(source))
        assertEquals(1, blocks.count { it.type == AgentRichBlockType.TABLE })
        assertTrue(blocks.single { it.type == AgentRichBlockType.CODE }.text.contains("| Example |"))
    }

    @Test fun explicitCodeAndOrdinaryPipesAreNotPromoted() {
        assertEquals(AgentRichBlockType.CODE,
            AgentRichContentCodec.decode(wrapped(markdown, AgentRichBlockType.CODE)).single().type)
        val text = "Choose A | B\nThis is not a table."
        assertEquals(text, AgentRichContentCodec.decode(wrapped(text)).single().text)
        assertEquals(AgentRichBlockType.TEXT,
            AgentRichContentCodec.decode(wrapped("```text\n$markdown\n```")).single().type)
    }

    @Test fun multipleTablesKeepOrderAndExplicitArtifacts() {
        val table = "| Name | State |\n| :--- | ---: |\n| Build | Passed |"
        val image = AgentRichBlock("image", AgentRichBlockType.IMAGE, uri = "https://example.com/result.png")
        val raw = AgentRichContentCodec.encode(listOf(
            AgentRichBlock("text", AgentRichBlockType.TEXT, text = "$table\n\nBetween\n\n$table"), image
        ))
        val blocks = AgentRichContentCodec.decode(raw)
        assertEquals(listOf(AgentRichBlockType.TABLE, AgentRichBlockType.TEXT,
            AgentRichBlockType.TABLE, AgentRichBlockType.IMAGE), blocks.map { it.type })
        assertEquals(image.uri, blocks.last().uri)
    }
}
