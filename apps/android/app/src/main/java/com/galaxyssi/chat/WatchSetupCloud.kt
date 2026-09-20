package com.galaxyssi.chat

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.TimeUnit

internal object WatchSetupCloud {
    fun validate(profile: JSONObject) {
        val uri = URI(profile.getString("endpoint"))
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null)
        require(when (profile.optString("api_style", "openai")) {
            "openai" -> uri.path.endsWith("/chat/completions")
            "anthropic" -> uri.path.endsWith("/messages")
            "gemini" -> uri.path.endsWith(":generateContent")
            else -> false
        })
        val model = profile.getString("model"); val key = profile.getString("api_key")
        require(model.isNotBlank() && model.length <= 128 && key.isNotBlank() && key.length <= 4096 && key.none { it == '\r' || it == '\n' })
    }
    fun test(profile: JSONObject): Boolean {
        validate(profile)
        val client = OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS).callTimeout(30, TimeUnit.SECONDS)
            .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
        val request = Request.Builder().url(profile.getString("endpoint"))
        val model = profile.getString("model"); val key = profile.getString("api_key")
        val body = JSONObject()
        when (profile.optString("api_style", "openai")) {
            "gemini" -> {
                val url = profile.getString("endpoint").toHttpUrl()
                request.url(url.newBuilder().setPathSegment(url.pathSegments.lastIndex, "$model:generateContent").build())
                request.header("x-goog-api-key", key)
                body.put("contents", JSONArray().put(JSONObject().put("parts", JSONArray().put(JSONObject().put("text", "Reply OK")))))
                    .put("generationConfig", JSONObject().put("maxOutputTokens", 16))
            }
            else -> {
                body.put("model", model).put("messages", JSONArray().put(JSONObject().put("role", "user").put("content", "Reply OK"))).put("stream", false)
                if (profile.optString("api_style") == "anthropic") {
                    request.header("x-api-key", key).header("anthropic-version", "2023-06-01"); body.put("max_tokens", 16)
                } else {
                    request.header("Authorization", "Bearer $key")
                    if (URI(profile.getString("endpoint")).host == "api.deepseek.com") body.put("thinking", JSONObject().put("type", "disabled"))
                }
            }
        }
        return client.newCall(request.post(body.toString().toRequestBody("application/json".toMediaType())).build()).execute().use { response ->
            if (!response.isSuccessful) false else {
                // Do not log provider output or credentials.
                val source = response.body?.source() ?: return@use false
                source.request(32769)
                if (source.buffer.size > 32768) false else {
                    val result = JSONObject(source.readUtf8())
                    !result.has("error") && (result.has("choices") || result.has("content") || result.has("candidates"))
                }
            }
        }
    }
}
