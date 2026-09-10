package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentImagePresentationTest {
    private val fallback = "\u56fe\u7247"
    private val caption = "\u9cad\u9c7c\u56fe\u7247"
    private val block = AgentRichBlock("image", AgentRichBlockType.IMAGE, title = "mackerel.jpg",
        uri = "https://example.com/mackerel.jpg", text = "outputs \u00b7 97.6 KB",
        metadata = mapOf("category" to "outputs", "sha256" to "unchanged"))

    @Test fun usesMatchingChineseLinkLabel() {
        val source = "[\u6253\u5f00/\u4e0b\u8f7d$caption](sandbox:/mnt/data/outputs/mackerel.jpg)"
        assertEquals(caption, title(block, source))
    }

    @Test fun keepsChineseNameWithoutFileExtension() {
        assertEquals(caption, title(block.copy(title = "$caption.jpg")))
    }

    @Test fun unknownEnglishNameUsesLocalizedFallback() {
        assertEquals(fallback, title(block))
    }

    @Test fun doesNotUseUnrelatedOrAmbiguousLabels() {
        assertEquals(fallback, title(block, "[$caption](https://example.com/other.jpg)"))
        assertEquals(fallback, title(block,
            "[$caption](https://a.example/mackerel.jpg) [\u5176\u4ed6\u56fe](https://b.example/mackerel.jpg)"))
    }

    @Test fun doesNotRenameDownloadOrChangeTransportMetadata() {
        val shown = AgentImagePresentation.annotate(listOf(block), "", true, fallback).single()
        assertEquals(block.title, shown.title)
        assertEquals(block.uri, shown.uri)
        assertEquals("unchanged", shown.metadata["sha256"])
    }

    @Test fun leavesEnglishInterfaceAndNonImageBlocksUnchanged() {
        assertEquals(listOf(block), AgentImagePresentation.annotate(listOf(block), "", false, "Image"))
        val file = block.copy(type = AgentRichBlockType.FILE)
        assertEquals(listOf(file), AgentImagePresentation.annotate(listOf(file), "", true, fallback))
    }

    @Test fun hidesGeneratedCategoryAndSizeFooter() {
        assertEquals("", AgentImagePresentation.caption(block))
        assertEquals("", AgentImagePresentation.caption(block.copy(text = "outputs \u00b7 2.1 MB", metadata = emptyMap())))
    }

    @Test fun preservesMeaningfulImageCaption() {
        assertEquals(caption, AgentImagePresentation.caption(block.copy(text = caption)))
        assertEquals("outputs are verified", AgentImagePresentation.caption(block.copy(text = "outputs are verified")))
    }

    private fun title(value: AgentRichBlock, source: String = ""): String = AgentImagePresentation.title(
        AgentImagePresentation.annotate(listOf(value), source, true, fallback).single(), fallback)
}
