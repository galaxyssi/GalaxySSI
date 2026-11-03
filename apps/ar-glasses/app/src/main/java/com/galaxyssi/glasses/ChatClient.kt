package com.galaxyssi.glasses

import android.content.Context
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
    fun validated(message: (Int) -> String): Profile {
        val uri = URI(endpoint)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null &&
            uri.rawQuery == null && uri.rawFragment == null) { message(R.string.glasses_copy_only_https_addresses_without_parameters_are_supported) }
        require(style in setOf("openai", "anthropic", "gemini")) { message(R.string.glasses_copy_unsupported_api_type) }
        require(when (style) {
            "anthropic" -> uri.path.endsWith("/messages")
            "gemini" -> uri.path.endsWith(":generateContent")
            else -> uri.path.endsWith("/chat/completions")
        }) { message(R.string.glasses_copy_api_address_does_not_match_its_type) }
        require(model.isNotBlank() && model.length <= 128 && key.isNotBlank() && key.length <= 4096 &&
            key.none { it == '\n' || it == '\r' }) { message(R.string.glasses_copy_invalid_model_or_key) }
        return this
    }
}

/** Compact direct API path, following the watch's three provider formats and bounded context. */
internal class ChatClient(private val context: Context) {
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS).callTimeout(100, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
    @Volatile private var active: Call? = null

    fun cancel() { active?.cancel() }

    fun answer(profile: Profile, turns: JSONArray): String {
        profile.validated { context.getString(it) }
        val messages = JSONArray()
        for (i in maxOf(0, turns.length() - 13) until turns.length()) {
            val turn = turns.optJSONObject(i) ?: continue
            if (turn.optString("role") in setOf("user", "assistant")) {
                messages.put(JSONObject().put("role", turn.getString("role"))
                    .put("content", turn.optString("text").take(6000)))
            }
        }
        val system = context.getString(R.string.glasses_copy_you_are_the_galaxyssi_ar_glasses_assistant_reply)
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
                if (!response.isSuccessful) throw IllegalStateException(context.getString(R.string.glasses_copy_api_returned_http, response.code))
                val stream = response.body?.byteStream() ?: throw IllegalStateException(context.getString(R.string.glasses_copy_api_returned_no_content))
                val output = java.io.ByteArrayOutputStream()
                stream.use { input ->
                    val buffer = ByteArray(4096)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        if (output.size() + n > 256_000) throw IllegalStateException(context.getString(R.string.glasses_copy_reply_is_too_long))
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
                if (answer.isBlank()) throw IllegalStateException(context.getString(R.string.glasses_copy_api_returned_an_empty_reply))
                return answer.take(32_000)
            }
        } finally { active = null }
    }
}
