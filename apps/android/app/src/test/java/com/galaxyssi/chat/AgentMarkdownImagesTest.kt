package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentMarkdownImagesTest {
    private val image = "![Mackerel](https://example.com/fish.jpg)"
    private fun parse(text: String) = AgentRichContentCodec.fromText(text)

    @Test fun imageBecomesAnImageBlock() {
        val block = parse(image).single()
        assertEquals(AgentRichBlockType.IMAGE, block.type)
        assertEquals("Mackerel", block.title)
        assertEquals("https://example.com/fish.jpg", block.uri)
    }

    @Test fun ordinaryLinksAreNotImages() {
        val text = "[Mackerel](https://example.com/fish.jpg)"
        assertEquals(text, parse(text).single().text)
        assertEquals(AgentRichBlockType.TEXT, parse(text).single().type)
    }

    @Test fun supportsParenthesesTitlesAndEncodedQueries() {
        val block = parse("![A](<https://example.com/fish_(1)?size=100&amp;x=2> \"Photo\")").single()
        assertEquals("https://example.com/fish_(1)?size=100&x=2", block.uri)
        assertEquals(AgentRichBlockType.IMAGE, block.type)
    }

    @Test fun keepsCodeAndEscapedImageSyntaxLiteral() {
        assertEquals(AgentRichBlockType.TEXT, parse("`$image`").single().type)
        assertEquals(AgentRichBlockType.CODE, parse("```markdown\n$image\n```").single().type)
        assertEquals(AgentRichBlockType.TEXT, parse("\\$image").single().type)
        assertEquals(AgentRichBlockType.TEXT, parse("~~~markdown\n$image\n~~~").single().type)
    }

    @Test fun preservesSurroundingTextAndMultipleImages() {
        val blocks = parse("Before $image middle ![B](https://example.com/b.png) after")
        assertEquals(listOf(AgentRichBlockType.TEXT, AgentRichBlockType.IMAGE,
            AgentRichBlockType.TEXT, AgentRichBlockType.IMAGE, AgentRichBlockType.TEXT), blocks.map { it.type })
        assertEquals(listOf("Before", "middle", "after"), blocks.filter { it.type == AgentRichBlockType.TEXT }.map { it.text })
    }

    @Test fun incompleteStreamDoesNotFetchPartialUrl() {
        assertEquals(AgentRichBlockType.TEXT, parse(image.dropLast(1)).single().type)
        assertEquals(AgentRichBlockType.IMAGE, parse(image).single().type)
    }

    @Test fun unsafeSourcesAreNotPromoted() {
        listOf("file:///sdcard/a.jpg", "content://private/a", "javascript:alert", "data:image/png;base64,a",
            "https://user:password@example.com/a.jpg").forEach {
            assertEquals(AgentRichBlockType.TEXT, parse("![A]($it)").single().type)
        }
    }

    @Test fun httpImageRemainsAnImageWithExplicitFailureFallback() {
        assertEquals(AgentRichBlockType.IMAGE, parse("![A](http://example.com/a.jpg)").single().type)
    }

    @Test fun finalAndReloadPreserveImageWithStableIdentity() {
        val source = "Before\n\n$image\n\nAfter"
        val raw = AgentRichContentCodec.encode(listOf(AgentRichBlock("final", AgentRichBlockType.TEXT,
            text = source, metadata = mapOf("origin" to "desktop"))))
        val final = AgentRichContentCodec.decode(raw)
        assertEquals(parse(source).map { it.type }, final.map { it.type })
        assertEquals(final, AgentRichContentCodec.decode(raw))
        assertEquals(final, AgentRichContentCodec.decode(AgentRichContentCodec.normalize(raw)))
        assertEquals("desktop", final.single { it.type == AgentRichBlockType.IMAGE }.metadata["origin"])
    }

    @Test fun tableAndImageCanCoexist() {
        val blocks = parse("| A | B |\n| --- | --- |\n| 1 | 2 |\n\n$image")
        assertEquals(listOf(AgentRichBlockType.TABLE, AgentRichBlockType.IMAGE), blocks.map { it.type })
    }
}
