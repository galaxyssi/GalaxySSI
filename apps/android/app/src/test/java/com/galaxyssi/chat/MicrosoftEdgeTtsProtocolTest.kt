package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest
import java.util.Locale

class MicrosoftEdgeTtsProtocolTest {
    @Test
    fun generatesTheSameTimeBoundTokenAsEdgeTts() {
        assertEquals(
            "2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2",
            MicrosoftEdgeTtsProtocol.secMsGec(1_700_000_000L)
        )
    }

    @Test
    fun websocketAndHeadersMatchCurrentEdgeReadAloudClient() {
        val url = MicrosoftEdgeTtsProtocol.websocketUrl("connection123", 1_700_000_000L)
        val headers = MicrosoftEdgeTtsProtocol.requestHeaders("ABC123")

        assertTrue(url.contains("ConnectionId=connection123"))
        assertTrue(url.contains("Sec-MS-GEC="))
        assertTrue(url.contains("Sec-MS-GEC-Version=2-143.0.3650.75"))
        assertTrue(headers.getValue("User-Agent").contains("Edg/143.0.0.0"))
        assertEquals("muid=ABC123;", headers["Cookie"])
    }

    @Test
    fun v2MatchesOneThousandUpstreamTimeWindows() {
        // Golden digest of 1,000 v2 tokens from edge-tts b2ffbdd9f43f28f03cc939b5de0f3964aa62d60e.
        val digest = MessageDigest.getInstance("SHA-256")
        repeat(1_000) { index ->
            val token = MicrosoftEdgeTtsProtocol.secMsGec(1_600_000_000L + index * 7_919L)
            assertTrue(token.matches(Regex("[0-9A-F]{16}-[0-9A-F]{64}")))
            digest.update(token.toByteArray(Charsets.US_ASCII))
        }
        assertEquals(
            "055FAF684D9A39972FF8B14D1B4B496AE92026B5E2575A54FAC82D2C65046469",
            digest.digest().joinToString("") { "%02X".format(Locale.ROOT, it.toInt() and 255) }
        )
    }

    @Test
    fun v2MatchesEpochBoundariesAndFutureDates() {
        val expected = mapOf(
            0L to "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6",
            299L to "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6",
            300L to "F7535A20A262E331-28675BF85C7106BBF20035A78FCB0B6890813EAD5C3B983EF3424931B720BABB",
            1_792_908_000L to "660D8AEBD2921C83-67437D45B7AF09FC11030ACE27D06F3ABCF5E3EFB594EA48EF592E80D2904420",
            2_147_483_647L to "96AE288915A09C99-EB52B45DB68387A1383783E40D42BBBD69D4DCCDF2540629BD4E7FB2E3287822",
            4_102_444_800L to "DD230DB44FEE2FD7-DA0D4FA797866E36C992FABB81DD2F9DB37EB74D675D63228277003DCD3F9F8C"
        )
        expected.forEach { (seconds, token) -> assertEquals("epoch=$seconds", token, MicrosoftEdgeTtsProtocol.secMsGec(seconds)) }
    }

    @Test
    fun v2IsIndependentOfLocaleAndConcurrentCalls() {
        val previous = Locale.getDefault()
        val pool = java.util.concurrent.Executors.newFixedThreadPool(4)
        try {
            Locale.setDefault(Locale.forLanguageTag("ar-EG"))
            val expected = MicrosoftEdgeTtsProtocol.secMsGec(1_700_000_000L)
            val jobs = (1..32).map {
                pool.submit<String> { MicrosoftEdgeTtsProtocol.secMsGec(1_700_000_000L) }
            }
            jobs.forEach { assertEquals(expected, it.get()) }
        } finally {
            Locale.setDefault(previous)
            pool.shutdownNow()
        }
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
