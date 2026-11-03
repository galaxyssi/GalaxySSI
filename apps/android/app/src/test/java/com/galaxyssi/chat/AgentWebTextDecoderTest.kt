package com.galaxyssi.chat

import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test
import java.nio.charset.Charset

class AgentWebTextDecoderTest {
    private val chinese = "\u73e0\u6d77\u5c0f\u533a\u4ecb\u7ecd\uff1a\u4ea4\u901a\u548c\u5468\u8fb9\u914d\u5957"

    @Test fun honorsHttpCharsetAndHtmlMetaWithoutGarbledChinese() {
        for (charset in listOf("GBK", "GB18030", "UTF-8")) {
            val bytes = "<html><meta charset='$charset'><title>$chinese</title><p>$chinese</p></html>"
                .toByteArray(Charset.forName(charset))
            for (type in listOf("text/html", "text/html; charset=$charset")) {
                val decoded = AgentWebTextDecoder.decode(bytes, type, "https://example.com")
                assertEquals(chinese, Jsoup.parse(decoded).title())
                assertEquals(chinese, Jsoup.parse(decoded).selectFirst("p")!!.text())
                assertFalse(decoded.contains('\uFFFD'))
            }
        }
    }

    @Test fun supportsLegacyHttpEquivAndBom() {
        val html = "<html><meta http-equiv='Content-Type' content='text/html; charset=gb2312'><p>$chinese</p></html>"
        assertEquals(chinese, Jsoup.parse(AgentWebTextDecoder.decode(html.toByteArray(Charset.forName("GB2312")),
            "text/html", "https://example.com")).selectFirst("p")!!.text())
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "<html><p>$chinese</p></html>".toByteArray()
        assertEquals(chinese, Jsoup.parse(AgentWebTextDecoder.decode(bom, "text/html", "https://example.com"))
            .selectFirst("p")!!.text())
    }

    @Test fun plainTextAndJsonRemainUnmodified() {
        for (text in listOf(chinese, "{\"value\":\"$chinese\"}", "a < b"))
            assertEquals(text, AgentWebTextDecoder.decode(text.toByteArray(), "application/json", "https://example.com"))
    }
}
