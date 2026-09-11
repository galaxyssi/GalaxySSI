package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRichContentUpdatePolicyTest {
    @Test fun parserGeneratedIdsDoNotInvalidateUnchangedImagesOrTables() {
        val original = listOf(AgentRichBlock("first", AgentRichBlockType.IMAGE, uri = "https://example.test/image.png"))
        assertTrue(AgentRichContentUpdatePolicy.sameContent(original, original.map { it.copy(id = "fresh") }))
        assertFalse(AgentRichContentUpdatePolicy.sameContent(original, original.map { it.copy(uri = "https://example.test/other.png") }))
    }

    @Test fun adjacentParagraphsRemainOneSelectableGroup() {
        val blocks = listOf(AgentRichBlock("a", AgentRichBlockType.TEXT, text = "One"),
            AgentRichBlock("b", AgentRichBlockType.HEADING, text = "Two"),
            AgentRichBlock("c", AgentRichBlockType.IMAGE, uri = "https://example.test/image.png"),
            AgentRichBlock("d", AgentRichBlockType.TEXT, text = "Three"))
        assertEquals(listOf(2, 1, 1), AgentRichContentUpdatePolicy.groups(blocks).map { it.size })
    }

    @Test fun activeControlsAndPlayersKeepTheirExistingFullBindingPath() {
        for (type in listOf(AgentRichBlockType.APPROVAL, AgentRichBlockType.FORM, AgentRichBlockType.VIDEO)) {
            assertFalse(AgentRichContentUpdatePolicy.supports(listOf(AgentRichBlock("a", type))))
        }
    }
}
