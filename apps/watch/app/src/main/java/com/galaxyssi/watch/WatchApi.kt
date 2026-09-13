package com.galaxyssi.watch

import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.util.UUID
import java.util.concurrent.TimeUnit

class ApiProfile(val endpoint: String, val model: String, val key: String, val id: String = UUID.randomUUID().toString(), val style: String = "openai") {
    init {
        val uri = URI(endpoint)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank())
        require(uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null)
        require(when (style) { "openai" -> uri.path.endsWith("/chat/completions"); "anthropic" -> uri.path.endsWith("/messages"); "gemini" -> uri.path.endsWith(":generateContent"); else -> false })
        require(model.isNotBlank() && model.length <= 128)
        require(key.isNotBlank() && key.length <= 4096 && key.none { it == '\r' || it == '\n' })
    }
    fun json(): JSONObject = JSONObject().put("endpoint", endpoint).put("model", model).put("api_key", key).put("id", id).put("api_style", style)
    override fun toString(): String = "ApiProfile(endpoint=$endpoint, model=$model, key=[redacted])"
    companion object {
        fun fromJson(j: JSONObject) = ApiProfile(j.getString("endpoint").trim(), j.getString("model").trim(),
            j.getString("api_key").trim(), j.optString("id").ifBlank { UUID.randomUUID().toString() }, j.optString("api_style", "openai"))
    }
}

class ApiFailure(val reason: Int) : Exception("API request failed")

/** Bounded text client for Android's three cloud protocols; no retry or redirects. */
class WatchApi(private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(15, TimeUnit.SECONDS).readTimeout(90, TimeUnit.SECONDS)
    .callTimeout(100, TimeUnit.SECONDS).retryOnConnectionFailure(false)
    .followRedirects(false).followSslRedirects(false).build()) {

    fun request(profile: ApiProfile, task: WatchTask, history: List<WatchTask>): Call {
        require(task.desktopId == "api" && task.routeId == profile.id)
        val messages = JSONArray()
        history.filter { it.conversationId == task.conversationId && it.desktopId == "api" &&
            it.routeId == profile.id && it.state == TaskState.COMPLETED && it.id != task.id }
            .sortedBy { it.sourceId }.takeLast(6).forEach {
                messages.put(JSONObject().put("role", "user").put("content", it.prompt))
                messages.put(JSONObject().put("role", "assistant").put("content", it.reply.take(6000)))
            }
        messages.put(JSONObject().put("role", "user").put("content", task.prompt))
        val request = Request.Builder().url(profile.endpoint).tag(String::class.java, profile.style)
        val body = when (profile.style) {
            "anthropic" -> {
                request.header("x-api-key", profile.key).header("anthropic-version", "2023-06-01")
                JSONObject().put("model", profile.model).put("messages", messages).put("max_tokens", 2048)
            }
            "gemini" -> {
                val url = profile.endpoint.toHttpUrl()
                request.url(url.newBuilder().setPathSegment(url.pathSegments.lastIndex, "${profile.model}:generateContent").build())
                request.header("x-goog-api-key", profile.key)
                val contents = JSONArray()
                for (i in 0 until messages.length()) {
                    val message = messages.getJSONObject(i)
                    contents.put(JSONObject().put("role", if (message.getString("role") == "assistant") "model" else "user")
                        .put("parts", JSONArray().put(JSONObject().put("text", message.getString("content")))))
                }
                JSONObject().put("contents", contents).put("generationConfig", JSONObject().put("maxOutputTokens", 2048))
            }
            else -> {
                request.header("Authorization", "Bearer ${profile.key}")
                JSONObject().put("model", profile.model).put("messages", messages).put("stream", false)
                    .apply {
                        if (profile.endpoint.toHttpUrl().host == "api.deepseek.com") {
                            put("thinking", JSONObject().put("type", "disabled"))
                            put("max_tokens", 2048)
                        }
                    }
            }
        }
        return client.newCall(request.post(body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())).build())
    }

    fun execute(call: Call): String = call.execute().use { response ->
        if (!response.isSuccessful) throw ApiFailure(when (response.code) {
            401, 403 -> R.string.api_auth_error
            429 -> R.string.api_rate_error
            400, 404, 422 -> R.string.api_model_error
            else -> R.string.api_request_error
        })
        val body = response.body ?: throw ApiFailure(R.string.api_response_error)
        val bytes = body.byteStream().use { stream ->
            val result = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) break
                if (result.size() + read > 256_000) throw ApiFailure(R.string.api_response_error)
                result.write(buffer, 0, read)
            }
            result.toByteArray()
        }
        val json = try { JSONObject(String(bytes, Charsets.UTF_8)) } catch (_: Exception) { throw ApiFailure(R.string.api_response_error) }
        val text = when (call.request().tag(String::class.java)) {
            "anthropic" -> textParts(json.optJSONArray("content"))
            "gemini" -> textParts(json.optJSONArray("candidates")?.optJSONObject(0)?.optJSONObject("content")?.optJSONArray("parts"))
            else -> {
                val message = json.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")
                if (message == null) "" else (if (message.isNull("content")) "" else message.optString("content"))
                    .ifBlank { message.optString("refusal") }
            }
        }
        text.takeIf { it.isNotBlank() }?.take(32_000) ?: throw ApiFailure(R.string.api_response_error)
    }
    private fun textParts(parts: JSONArray?): String = buildString {
        if (parts != null) for (i in 0 until parts.length()) {
            val part = parts.optJSONObject(i) ?: continue
            if (!part.optBoolean("thought") && !part.isNull("text")) append(part.optString("text"))
        }
    }
}
