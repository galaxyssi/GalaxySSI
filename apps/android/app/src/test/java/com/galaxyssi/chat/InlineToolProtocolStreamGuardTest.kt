package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class InlineToolProtocolStreamGuardTest {
    @Test
    fun streamsNormalTextWithoutDelay() {
        val guard = InlineToolProtocolStreamGuard()

        assertEquals("Zhuhai weather", guard.append("Zhuhai weather"))
        assertEquals(" is sunny.", guard.append(" is sunny."))
        assertEquals("", guard.finishVisibleText())
        assertEquals("Zhuhai weather is sunny.", guard.rawText())
    }

    @Test
    fun suppressesDsmlProtocolSplitAcrossNetworkDeltas() {
        val guard = InlineToolProtocolStreamGuard()
        val fragments = listOf(
            "I will check the live forecast.\n<",
            "\uff5cDS",
            "ML\uff5ctool_calls><\uff5cDSML\uff5cinvoke name=\"web_fetch\"><\uff5cDSML\uff5cparameter name=\"url\">",
            "https://api.open-meteo.com/v1/forecast?latitude=22.27",
            "</\uff5cDSML\uff5cparameter></\uff5cDSML\uff5cinvoke></\uff5cDSML\uff5ctool_calls>"
        )

        val visible = fragments.joinToString("") { guard.append(it) } + guard.finishVisibleText()

        assertEquals("I will check the live forecast.\n", visible)
        assertTrue(CloudWebGrounding.containsInternalToolProtocol(guard.rawText()))
        assertEquals(1, CloudWebGrounding.parseInlineToolCalls(guard.rawText()).size)
        assertFalse(visible.contains("DSML"))
        assertFalse(visible.contains("open-meteo"))
    }

    @Test
    fun preservesOrdinaryAngleBracketText() {
        val guard = InlineToolProtocolStreamGuard()

        val visible = guard.append("Use <b>") + guard.append("bold</b> text") + guard.finishVisibleText()

        assertEquals("Use <b>bold</b> text", visible)
    }
}
