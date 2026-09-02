package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MicrosoftEdgeTtsProtocolTest {
    @Test
    fun generatesTheSameTimeBoundTokenAsEdgeTts() {
        assertEquals(
            "42301B335578FEFDAE2637DED1ABD614505D432559EC08032B82048483726AFF",
            MicrosoftEdgeTtsProtocol.secMsGec(1_700_000_000L)
        )
    }

    @Test
    fun websocketAndHeadersMatchCurrentEdgeReadAloudClient() {
        val url = MicrosoftEdgeTtsProtocol.websocketUrl("connection123", 1_700_000_000L)
        val headers = MicrosoftEdgeTtsProtocol.requestHeaders("ABC123")

        assertTrue(url.contains("ConnectionId=connection123"))
        assertTrue(url.contains("Sec-MS-GEC="))
        assertTrue(url.contains("Sec-MS-GEC-Version=1-143.0.3650.75"))
        assertTrue(headers.getValue("User-Agent").contains("Edg/143.0.0.0"))
        assertEquals("muid=ABC123;", headers["Cookie"])
    }

    @Test
    fun messagesRequestPythonEdgeTtsAudioAndNeutralProsody() {
        val config = MicrosoftEdgeTtsProtocol.speechConfigMessage(0L)
        val ssml = MicrosoftEdgeTtsProtocol.ssmlMessage(
            "request123",
            "A&B <test>\u0001",
            MicrosoftTtsVoiceCatalog.XIAOXIAO,
            0L
        )

        assertTrue(config.contains("audio-24khz-48kbitrate-mono-mp3"))
        assertTrue(ssml.contains("pitch='+0Hz' rate='+0%' volume='+0%'"))
        assertTrue(ssml.contains("A&amp;B &lt;test&gt; "))
        assertFalse(ssml.contains('\u0001'))
        assertTrue(ssml.contains("Thu Jan 01 1970 00:00:00 GMT+0000"))
    }
}
