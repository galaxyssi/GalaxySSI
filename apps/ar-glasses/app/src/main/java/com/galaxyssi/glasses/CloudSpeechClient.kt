package com.galaxyssi.glasses

import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.TimeUnit

internal data class AsrProxyConfig(val endpoint: String, val token: String) {
    fun validated(): AsrProxyConfig {
        val uri = URI(endpoint)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null &&
            uri.rawQuery == null && uri.rawFragment == null && uri.path == "/transcribe") {
            "语音代理需使用 HTTPS /transcribe 地址"
        }
        require(token.length in 32..256 && token.all { it.code in 33..126 } &&
            token.none { it == '\r' || it == '\n' }) { "语音代理令牌无效" }
        return this
    }
}

/** Sends only the post-wake utterance to the user-configured speech proxy. */
internal class CloudSpeechClient {
    private val client = OkHttpClient.Builder().connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS).callTimeout(24, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
    @Volatile private var active: Call? = null

    fun cancel() { active?.cancel() }

    fun transcribe(config: AsrProxyConfig, pcm: ShortArray): String {
        config.validated()
        val wav = wav(pcm)
        val request = Request.Builder().url(config.endpoint)
            .header("Authorization", "Bearer ${config.token}")
            .header("Cache-Control", "no-store")
            .post(wav.toRequestBody("audio/wav".toMediaType())).build()
        val call = client.newCall(request)
        active = call
        try {
            call.execute().use { response ->
                if (!response.isSuccessful) error("语音代理返回 HTTP ${response.code}")
                val body = response.body ?: error("语音代理未返回内容")
                require(body.contentLength() <= 16_384) { "语音代理回复过长" }
                val output = java.io.ByteArrayOutputStream()
                body.byteStream().use { stream ->
                    val buffer = ByteArray(2048)
                    while (true) {
                        val n = stream.read(buffer)
                        if (n < 0) break
                        require(output.size() + n <= 16_384) { "语音代理回复过长" }
                        output.write(buffer, 0, n)
                    }
                }
                val text = JSONObject(output.toString("UTF-8")).optString("text").trim()
                require(text.isNotBlank()) { "云端没有识别到语音" }
                return text.take(4000)
            }
        } finally { if (active === call) active = null }
    }

    companion object {
        fun wav(pcm: ShortArray): ByteArray {
            require(pcm.size in 1600..330000) { "语音长度需为 0.1 至约 20 秒" }
            val dataSize = pcm.size * 2
            val bytes = ByteArray(44 + dataSize)
            fun ascii(at: Int, value: String) { value.forEachIndexed { i, c -> bytes[at + i] = c.code.toByte() } }
            fun u16(at: Int, value: Int) {
                bytes[at] = value.toByte(); bytes[at + 1] = (value ushr 8).toByte()
            }
            fun u32(at: Int, value: Int) { for (i in 0..3) bytes[at + i] = (value ushr (i * 8)).toByte() }
            ascii(0, "RIFF"); u32(4, dataSize + 36); ascii(8, "WAVE")
            ascii(12, "fmt "); u32(16, 16); u16(20, 1); u16(22, 1)
            u32(24, 16000); u32(28, 32000); u16(32, 2); u16(34, 16)
            ascii(36, "data"); u32(40, dataSize)
            pcm.forEachIndexed { i, sample -> u16(44 + i * 2, sample.toInt()) }
            return bytes
        }
    }
}
