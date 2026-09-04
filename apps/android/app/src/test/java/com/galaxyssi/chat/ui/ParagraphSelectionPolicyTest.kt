package com.galaxyssi.chat.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ParagraphSelectionPolicyTest {
    @Test
    fun selectsTheEntireParagraphAroundTheCursor() {
        val text = "第一段内容\n第二段可以跨行选择\n第三段"

        assertEquals(
            ParagraphTextRange(6, 15),
            ParagraphSelectionPolicy.rangeAt(text, 10)
        )
    }

    @Test
    fun newlineAtTheEndOfAParagraphSelectsThePreviousParagraph() {
        val text = "first paragraph\nsecond paragraph"

        assertEquals(
            ParagraphTextRange(0, 15),
            ParagraphSelectionPolicy.rangeAt(text, 15)
        )
    }

    @Test
    fun endCursorSelectsTheLastParagraph() {
        val text = "first\nlast paragraph"

        assertEquals(
            ParagraphTextRange(6, text.length),
            ParagraphSelectionPolicy.rangeAt(text, text.length)
        )
    }

    @Test
    fun emptyInputHasNoSelection() {
        assertEquals(
            ParagraphTextRange(0, 0),
            ParagraphSelectionPolicy.rangeAt("", 0)
        )
    }
}
