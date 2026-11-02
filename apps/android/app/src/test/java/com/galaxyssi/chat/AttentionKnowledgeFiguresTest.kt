package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AttentionKnowledgeFiguresTest {
    @Test fun figureModePreservesCaptionsOrderingAndAttributionWithoutInventingText() {
        val document = AttentionArticleDocument(listOf(
            AttentionArticleBlock("heading", "Cell membrane"), AttentionArticleBlock("paragraph", "Long explanation"),
            AttentionArticleBlock("image", "Animal", "https://example.org/a.png"),
            AttentionArticleBlock("image", "Plant", "https://example.org/b.png"),
            AttentionArticleBlock("caption", "Figure 1: cells. Credit: Author."),
            AttentionArticleBlock("paragraph", "More scientific prose"),
            AttentionArticleBlock("heading", "Nucleus"), AttentionArticleBlock("image", "Nucleus", "https://example.org/c.png"),
            AttentionArticleBlock("attribution", "Open textbook", "https://creativecommons.org/licenses/by/4.0/")))
        val figures = AttentionKnowledgeFigures.extract(document)!!
        assertEquals(listOf("heading", "image", "image", "caption", "heading", "image", "caption", "attribution"), figures.blocks.map { it.kind })
        assertEquals("Nucleus", figures.blocks[6].text)
        assertEquals(document.blocks.filter { it.kind == "image" }, figures.blocks.filter { it.kind == "image" })
        assertTrue(document.body.contains("Long explanation"))
        assertFalse(figures.body.contains("Long explanation"))
    }

    @Test fun textOnlyMaterialDoesNotGetAnArtificialDiagram() {
        assertNull(AttentionKnowledgeFigures.extract(AttentionArticleDocument.plain("Biology text")))
    }

    @Test fun allCaptionFragmentsAndImageDimensionsSurvive() {
        val image = AttentionArticleBlock("image", "Cells", "https://example.org/cells.png", 1200, 1600)
        val document = AttentionArticleDocument(listOf(image, AttentionArticleBlock("caption", "Figure 2"),
            AttentionArticleBlock("caption", "Source and explanation")))
        assertEquals(document, AttentionKnowledgeFigures.extract(document))
    }
}
