package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentInlineMarkdownTest {
    @Test fun angleDelimitedCitationShowsOnlyItsLabelAndKeepsExactTarget() {
        val url = "https://example.com/report_(revision)?a=one&signature=x*y"
        val segments = AgentInlineMarkdown.parse("Result [12](<$url>).")
        assertEquals("Result 12.", segments.joinToString("") { it.text })
        assertEquals(url, segments.single { it.style == AgentInlineStyle.LINK }.url)
    }

    @Test fun malformedOrNonWebAngleLinksDoNotBecomeClickable() {
        for (value in listOf("[x](<https://example.com/)", "[x](https://example.com/>)",
            "[x](<javascript:alert(1)>)", "[x](<https://example.com/a b>)")) {
            assertEquals(value, 0, AgentInlineMarkdown.parse(value).count { it.style == AgentInlineStyle.LINK })
        }
    }

    @Test
    fun parsesBoldCodeAndLinksWithoutLeavingMarkdownMarkers() {
        val segments = AgentInlineMarkdown.parse(
            "Today is **cloudy**. Run `status` and open [Shanghai Weather](https://sh.cma.gov.cn/)."
        )

        assertEquals(
            "Today is cloudy. Run status and open Shanghai Weather.",
            segments.joinToString("") { it.text }
        )
        assertEquals(AgentInlineStyle.BOLD, segments.first { it.text == "cloudy" }.style)
        assertEquals(AgentInlineStyle.CODE, segments.first { it.text == "status" }.style)
        assertEquals(
            "https://sh.cma.gov.cn/",
            segments.first { it.text == "Shanghai Weather" }.url
        )
    }

    @Test
    fun parsesItalicAndStrikeWithoutAffectingBold() {
        val segments = AgentInlineMarkdown.parse("Use *care* and remove ~~noise~~ while **keeping this**.")

        assertEquals(AgentInlineStyle.ITALIC, segments.first { it.text == "care" }.style)
        assertEquals(AgentInlineStyle.STRIKE, segments.first { it.text == "noise" }.style)
        assertEquals(AgentInlineStyle.BOLD, segments.first { it.text == "keeping this" }.style)
    }
}
