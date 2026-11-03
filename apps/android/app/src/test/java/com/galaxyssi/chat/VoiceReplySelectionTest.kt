package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.SpeechTextNormalizer
import org.junit.Assert.*
import org.junit.Test

class VoiceReplySelectionTest {
    private fun entry(text: String = "第一段。\n\n第二段。\n\n第三段。") = AgentTranscriptEntry(
        "reply", AgentTranscriptRole.ASSISTANT, text, 1L, conversationId = "conversation", turnId = "turn")

    @Test fun readsOnlyTheSelectedPersistedAssistantReply() {
        val selected = VoiceReplySelection("conversation", "reply")
        assertEquals(SpeechTextNormalizer.normalize(entry().text), selected.text(entry()))
        assertNull(selected.text(null))
        assertNull(selected.text(entry().copy(conversationId = "other")))
        assertNull(selected.text(entry().copy(id = "other")))
        assertNull(selected.text(entry().copy(role = AgentTranscriptRole.USER)))
        assertNull(selected.text(entry().copy(role = AgentTranscriptRole.PROCESS)))
    }

    @Test fun streamingAndInternalEntriesStayOnTheirExistingPath() {
        val stream = entry().copy(id = "agent-stream-turn")
        assertNull(VoiceReplySelection(stream.conversationId, stream.id).text(stream))
        assertNull(VoiceReplySelection("conversation", "reply").text(entry().copy(dedupeKey = "approval:turn")))
        assertNull(VoiceReplySelection("conversation", "reply").text(entry("")))
    }

    @Test fun secondParagraphReadsThroughTheEnd() {
        val entry = entry()
        val selected = VoiceReplySelection.fromParagraph(entry, entry.text, entry.text.indexOf("第二段"))!!
        assertEquals("第二段。 第三段。", selected.text(entry)!!.substring(selected.offset))
    }

    @Test fun repeatedParagraphUsesTheSelectedOccurrence() {
        val entry = entry("相同。\n\n相同。\n\n结尾。")
        val selected = VoiceReplySelection.fromParagraph(entry, entry.text, entry.text.lastIndexOf("相同"))!!
        assertEquals("相同。 结尾。", selected.text(entry)!!.substring(selected.offset))
        assertTrue(selected.offset > 0)
    }

    @Test fun renderedSectionMapsIntoTheFullReply() {
        val entry = entry()
        val source = "第二段。\n\n第三段。"
        val selected = VoiceReplySelection.fromParagraph(entry, source, source.indexOf("第三段"))!!
        assertEquals("第三段。", selected.text(entry)!!.substring(selected.offset))
        assertNull(VoiceReplySelection.fromParagraph(entry, "另一条回复。", 0))
        assertNull(VoiceReplySelection.fromParagraph(entry, source, -1))
        assertNull(VoiceReplySelection.fromParagraph(entry, source, source.length + 1))
    }

    @Test fun markdownAndBlankLinesDoNotCutTheNextWord() {
        val entry = entry("**第一段**。\n\n第二段内容。\n\n最后一段。")
        val selected = VoiceReplySelection.fromParagraph(entry, entry.text, entry.text.indexOf("第二段"))!!
        assertTrue(selected.text(entry)!!.substring(selected.offset).startsWith("第二段内容"))
    }

    @Test fun renderedMarkdownSectionStillMapsToItsParagraph() {
        val entry = entry("**第一段**。\n\n**第二段**内容。\n\n最后一段。")
        val rendered = "第二段内容。\n\n最后一段。"
        val selected = VoiceReplySelection.fromParagraph(entry, rendered, rendered.indexOf("最后"))!!
        assertEquals("最后一段。", selected.text(entry)!!.substring(selected.offset))
    }

    @Test fun newsBookmarkOffsetIsExplicitAndNeverImplicitlyShared() {
        val queue = VoiceNewsQueue()
        queue.replace(listOf("reply"), 20)
        assertEquals(20, queue.checkpoint.offset)
        queue.replace(listOf("news"))
        assertEquals(0, queue.checkpoint.offset)
        assertEquals("news", queue.articleId)
    }
}
