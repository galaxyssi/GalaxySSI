package com.galaxyssi.glasses

import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.TimeUnit

internal data class Profile(val endpoint: String, val model: String, val key: String, val style: String) {
    fun validated(): Profile {
        val uri = URI(endpoint)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null &&
            uri.rawQuery == null && uri.rawFragment == null) { "仅支持不含参数的 HTTPS 地址" }
        require(style in setOf("openai", "anthropic", "gemini")) { "不支持的接口类型" }
        require(when (style) {
            "anthropic" -> uri.path.endsWith("/messages")
            "gemini" -> uri.path.endsWith(":generateContent")
            else -> uri.path.endsWith("/chat/completions")
        }) { "接口地址与类型不匹配" }
        require(model.isNotBlank() && model.length <= 128 && key.isNotBlank() && key.length <= 4096 &&
            key.none { it == '\n' || it == '\r' }) { "模型或密钥无效" }
        return this
    }
}

/** Compact direct API path, following the watch's three provider formats and bounded context. */
internal class ChatClient {
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS).callTimeout(100, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
    @Volatile private var active: Call? = null

    fun cancel() { active?.cancel() }

    fun answer(profile: Profile, turns: JSONArray): String {
        profile.validated()
        val messages = JSONArray()
        for (i in maxOf(0, turns.length() - 13) until turns.length()) {
            val turn = turns.optJSONObject(i) ?: continue
            if (turn.optString("role") in setOf("user", "assistant")) {
                messages.put(JSONObject().put("role", turn.getString("role"))
                    .put("content", turn.optString("text").take(6000)))
            }
        }
        val system = "你是 GalaxySSI AR 眼镜助手。回答简洁、适合横屏阅读和语音播报；按用户语言回答。"
        val request = Request.Builder().url(profile.endpoint)
        val body = when (profile.style) {
            "anthropic" -> {
                request.header("x-api-key", profile.key).header("anthropic-version", "2023-06-01")
                JSONObject().put("model", profile.model).put("system", system)
                    .put("max_tokens", 2048).put("messages", messages)
            }
            "gemini" -> {
                request.header("x-goog-api-key", profile.key)
                val contents = JSONArray()
                for (i in 0 until messages.length()) {
                    val item = messages.getJSONObject(i)
                    contents.put(JSONObject().put("role", if (item.getString("role") == "assistant") "model" else "user")
                        .put("parts", JSONArray().put(JSONObject().put("text", item.getString("content")))))
                }
                JSONObject().put("systemInstruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", system))))
                    .put("contents", contents).put("generationConfig", JSONObject().put("maxOutputTokens", 2048))
            }
            else -> {
                request.header("Authorization", "Bearer ${profile.key}")
                val all = JSONArray().put(JSONObject().put("role", "system").put("content", system))
                for (i in 0 until messages.length()) all.put(JSONObject().put("role", messages.getJSONObject(i).getString("role"))
                    .put("content", messages.getJSONObject(i).getString("content")))
                JSONObject().put("model", profile.model).put("messages", all).put("stream", false)
            }
        }
        val call = client.newCall(request.post(body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())).build())
        active = call
        try {
            call.execute().use { response ->
                if (!response.isSuccessful) throw IllegalStateException("接口返回 HTTP ${response.code}")
                val stream = response.body?.byteStream() ?: throw IllegalStateException("接口没有返回内容")
                val output = java.io.ByteArrayOutputStream()
                stream.use { input ->
                    val buffer = ByteArray(4096)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        if (output.size() + n > 256_000) throw IllegalStateException("回复过长")
                        output.write(buffer, 0, n)
                    }
                }
                val json = JSONObject(output.toString("UTF-8"))
                val answer = when (profile.style) {
                    "anthropic" -> json.optJSONArray("content")?.optJSONObject(0)?.optString("text")
                    "gemini" -> json.optJSONArray("candidates")?.optJSONObject(0)?.optJSONObject("content")
                        ?.optJSONArray("parts")?.optJSONObject(0)?.optString("text")
                    else -> json.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.optString("content")
                }.orEmpty().trim()
                if (answer.isBlank()) throw IllegalStateException("接口返回了空回复")
                return answer.take(32_000)
            }
        } finally { active = null }
    }
}
