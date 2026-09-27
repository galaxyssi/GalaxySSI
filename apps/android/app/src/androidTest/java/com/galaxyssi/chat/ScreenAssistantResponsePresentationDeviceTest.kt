package com.galaxyssi.chat

import android.text.Spanned
import android.text.style.StyleSpan
import android.text.style.URLSpan
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ScreenAssistantResponsePresentationDeviceTest {
    @Test fun longSourceUrlDisplaysItsTitleAndPreservesBoldText() {
        val url = "https://example.com/article?query=" + "evidence".repeat(200)
        val result = AgentRichInlineMarkdownRenderer.render("**Product** [Official source]($url)") as Spanned
        assertEquals("Product Official source", result.toString())
        assertEquals(1, result.getSpans(0, result.length, StyleSpan::class.java).size)
        assertEquals(url, result.getSpans(0, result.length, URLSpan::class.java).single().url)
    }

}
