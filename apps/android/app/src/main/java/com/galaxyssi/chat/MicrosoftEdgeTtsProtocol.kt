package com.galaxyssi.chat

import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

internal object MicrosoftEdgeTtsProtocol {
    private const val BASE_URL =
        "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
    private const val TRUSTED_CLIENT_TOKEN = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private const val WINDOWS_EPOCH_SECONDS = 11_644_473_600L
    private const val GEC_WINDOW_SECONDS = 300L
    private const val FILETIME_TICKS_PER_SECOND = 10_000_000L
    private const val CHROMIUM_FULL_VERSION = "143.0.3650.75"
    private const val CHROMIUM_MAJOR_VERSION = "143"
    private const val SEC_MS_GEC_VERSION = "1-$CHROMIUM_FULL_VERSION"

    fun websocketUrl(connectionId: String, epochSeconds: Long): String =
        "$BASE_URL?TrustedClientToken=$TRUSTED_CLIENT_TOKEN" +
            "&ConnectionId=$connectionId" +
            "&Sec-MS-GEC=${secMsGec(epochSeconds)}" +
            "&Sec-MS-GEC-Version=$SEC_MS_GEC_VERSION"

    fun requestHeaders(muid: String): Map<String, String> = linkedMapOf(
        "Pragma" to "no-cache",
        "Cache-Control" to "no-cache",
        "Origin" to "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
        "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$CHROMIUM_MAJOR_VERSION.0.0.0 " +
            "Safari/537.36 Edg/$CHROMIUM_MAJOR_VERSION.0.0.0",
        "Accept-Encoding" to "gzip, deflate, br, zstd",
        "Accept-Language" to "en-US,en;q=0.9",
        "Cookie" to "muid=$muid;"
    )

    fun secMsGec(epochSeconds: Long): String {
        val roundedSeconds = Math.floorDiv(epochSeconds, GEC_WINDOW_SECONDS) * GEC_WINDOW_SECONDS
        val ticks = Math.multiplyExact(
            Math.addExact(roundedSeconds, WINDOWS_EPOCH_SECONDS),
            FILETIME_TICKS_PER_SECOND
        )
        return MessageDigest.getInstance("SHA-256")
            .digest("$ticks$TRUSTED_CLIENT_TOKEN".toByteArray(Charsets.US_ASCII))
            .joinToString("") { "%02X".format(Locale.US, it.toInt() and 0xff) }
    }

    fun speechConfigMessage(epochMillis: Long = System.currentTimeMillis()): String =
        "X-Timestamp:${timestamp(epochMillis)}\r\n" +
            "Content-Type:application/json; charset=utf-8\r\n" +
            "Path:speech.config\r\n\r\n" +
            "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{" +
            "\"sentenceBoundaryEnabled\":\"true\",\"wordBoundaryEnabled\":\"false\"}," +
            "\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"

    fun ssmlMessage(
        requestId: String,
        text: String,
        voice: String,
        epochMillis: Long = System.currentTimeMillis()
    ): String {
        val escaped = sanitize(text)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
        val ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' " +
            "xml:lang='en-US'><voice name='$voice'><prosody pitch='+0Hz' rate='+0%' " +
            "volume='+0%'>$escaped</prosody></voice></speak>"
        return "X-RequestId:$requestId\r\n" +
            "Content-Type:application/ssml+xml\r\n" +
            "X-Timestamp:${timestamp(epochMillis)}Z\r\n" +
            "Path:ssml\r\n\r\n$ssml"
    }

    fun timestamp(epochMillis: Long): String = DateTimeFormatter
        .ofPattern("EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'", Locale.US)
        .format(Instant.ofEpochMilli(epochMillis).atZone(ZoneOffset.UTC))

    private fun sanitize(text: String): String = buildString(text.length) {
        text.forEach { char ->
            val code = char.code
            append(if (code in 0..8 || code in 11..12 || code in 14..31) ' ' else char)
        }
    }
}
