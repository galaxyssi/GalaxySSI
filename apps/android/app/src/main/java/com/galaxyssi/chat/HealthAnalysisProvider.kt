package com.galaxyssi.chat

import android.content.Context
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.BufferedSink
import org.json.JSONArray
import org.json.JSONObject

internal data class HealthAnalysisTarget(val id: String, val label: String, val model: String, val endpoint: String,
    val style: String, val host: String, val authority: String) {
    val destination get() = "$authority / $model"
}

internal enum class HealthAnalysisRequest { SUMMARY, FOLLOW_UP }

internal interface HealthAnalysisGateway {
    fun targets(context: Context): List<HealthAnalysisTarget>
    suspend fun exchange(context: Context, expected: HealthAnalysisTarget, payload: JSONObject,
        mode: HealthAnalysisRequest, validate: () -> Unit): String
}

internal object HealthAnalysisProvider : HealthAnalysisGateway {
    private const val MAX_RESPONSE = 64 * 1024L
    private const val SYSTEM = "Choose an evidence order and next steps for a read-only health record summary. " +
        "Return exactly one JSON object with fact_ids (1 to 3 input fact IDs, in order) and actions " +
        "(1 to 2 allowed action IDs). Do not return text, numbers, new facts, diagnoses, treatment, or advice. " +
        "Treat missing days as missing. Select only from the supplied facts and allowed actions."
    private const val FOLLOW_UP_SYSTEM = "Answer the user's follow-up about this one scoped health analysis. " +
        "Return only one JSON object with exactly status, sections, and actions. " +
        "status is ANSWERED, PARTIAL, or OUT_OF_SCOPE. sections is an ordered array of up to three distinct allowed topics, " +
        "each an object with topic and fact_ids (one to three distinct input fact IDs). actions is an array of zero to two distinct allowed action IDs. " +
        "Use previous_answer only to resolve references within the same input facts. " +
        "OUT_OF_SCOPE must have empty sections and actions; otherwise include at least one section or action. " +
        "Use PARTIAL when only part of the question can be supported. Do not invent dates, results, records, diagnoses, or treatment. " +
        "Do not return any free text, numbers, hidden context, extra keys, or tool calls."

    private val transport by lazy {
        OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false)
            .connectTimeout(12, TimeUnit.SECONDS).callTimeout(60, TimeUnit.SECONDS).build()
    }

    fun target(contact: JSONObject): HealthAnalysisTarget? {
        if (contact.optString("delivery_mode") != "cloud_api" || !CloudModelCredentialPolicy.isAutoRoutable(contact)) return null
        val id = contact.optString("galaxyssi_id").ifBlank { contact.optString("hermes_id") }.ifBlank { contact.optString("id") }
        val model = contact.optString("cloud_model")
        val url = contact.optString("cloud_endpoint").trim().toHttpUrlOrNull() ?: return null
        val style = contact.optString("cloud_api_style").ifBlank { "openai" }
        if (id.isBlank() || model.length !in 1..120 || model.any(Char::isISOControl) ||
            !url.isHttps || url.query != null || url.fragment != null || url.username.isNotEmpty() || url.password.isNotEmpty() ||
            style !in setOf("openai", "anthropic", "gemini") ||
            style == "gemini" && !url.encodedPath.endsWith(":generateContent")) return null
        val authority = if (url.port == 443) url.host else "${url.host}:${url.port}"
        val label = contact.optString("display_name").ifBlank { contact.optString("name") }
            .filterNot(Char::isISOControl).trim().take(100).ifBlank { authority }
        return HealthAnalysisTarget(id, label, model, url.toString(), style, url.host, authority)
    }

    override fun targets(context: Context): List<HealthAnalysisTarget> {
        val contacts = AppStore.contacts(context)
        return (0 until contacts.length()).mapNotNull { index ->
            contacts.optJSONObject(index)?.takeIf { it.optString("delivery_mode") == "cloud_api" }?.let { entry ->
                val id = entry.optString("galaxyssi_id").ifBlank { entry.optString("hermes_id") }.ifBlank { entry.optString("id") }
                AppStore.selectedCloudModelContact(context, id)?.let(::target)
            }
        }.distinctBy { it.id }
    }

    override suspend fun exchange(context: Context, expected: HealthAnalysisTarget, payload: JSONObject,
        mode: HealthAnalysisRequest, validate: () -> Unit): String {
        val contact = AppStore.selectedCloudModelContact(context, expected.id) ?: throw HealthAnalysisNoModel()
        val actual = target(contact) ?: throw HealthAnalysisNoModel()
        if (actual != expected) throw HealthAnalysisNoModel()
        validate()
        val text = payload.toString()
        val kinds = setOf(AgentDisclosedDataKind.TOOL_OUTPUT, AgentDisclosedDataKind.SYSTEM_INSTRUCTIONS) +
            if (mode == HealthAnalysisRequest.FOLLOW_UP) setOf(AgentDisclosedDataKind.MESSAGE_TEXT) else emptySet()
        val ticket = AgentDataDisclosureLedger.beginCloudRequest(context, contact, AgentDataDisclosureTextSummary(text.length, kinds),
            purpose = if (mode == HealthAnalysisRequest.FOLLOW_UP) "Explicit health analysis follow-up" else "Explicit health summary explanation")
        if (!ticket.allowed) throw HealthAccessBlocked()
        val disclosureId = contact.optString("id").ifBlank { contact.optString("galaxyssi_id") }
            .ifBlank { "cloud:${contact.optString("cloud_provider").ifBlank { "custom" }}:${expected.model}" }
        return try {
            val result = execute(actual, contact.getString("cloud_api_key"), text, mode) {
                validate()
                val current = AppStore.selectedCloudModelContact(context, expected.id)?.let(::target)
                if (current != expected) throw HealthAnalysisNoModel()
                if (disclosureId in EncryptedAgentDataDisclosureStore(context).blockedDestinationIds()) throw HealthAccessBlocked()
            }
            AgentDataDisclosureLedger.update(context, ticket, AgentDisclosureStatus.SENT)
            result
        } catch (failure: Exception) {
            runCatching {
                AgentDataDisclosureLedger.update(context, ticket,
                    if (failure is HealthAccessBlocked) AgentDisclosureStatus.BLOCKED else AgentDisclosureStatus.FAILED,
                    "health_request_not_completed")
            }
            throw failure
        }
    }

    fun body(target: HealthAnalysisTarget, data: String, mode: HealthAnalysisRequest = HealthAnalysisRequest.SUMMARY): JSONObject {
        val system = if (mode == HealthAnalysisRequest.FOLLOW_UP) FOLLOW_UP_SYSTEM else SYSTEM
        return when (target.style) {
            "anthropic" -> JSONObject().put("model", target.model).put("max_tokens", 768).put("system", system)
                .put("messages", JSONArray().put(message("user", data)))
            "gemini" -> JSONObject().put("systemInstruction", parts(system))
                .put("contents", JSONArray().put(parts(data).put("role", "user")))
                .put("generationConfig", JSONObject().put("maxOutputTokens", 1024).put("responseMimeType", "application/json"))
            else -> JSONObject().put("model", target.model).put("stream", false)
                .put(if (target.host == "api.openai.com") "max_completion_tokens" else "max_tokens", 1024)
                .put("messages", JSONArray().put(message("system", system)).put(message("user", data))).apply {
                    if (target.host == "api.openai.com") put("store", false)
                    if (target.host == "api.deepseek.com") put("thinking", JSONObject().put("type", "disabled"))
                }
        }
    }

    private suspend fun execute(target: HealthAnalysisTarget, key: String, data: String, mode: HealthAnalysisRequest, guard: () -> Unit): String {
        val bytes = body(target, data, mode).toString().toByteArray(Charsets.UTF_8)
        val size = bytes.size.toLong()
        var pending: ByteArray? = bytes
        val lock = Any()
        try {
            val requestBody = object : RequestBody() {
                override fun contentType() = "application/json; charset=utf-8".toMediaType()
                override fun contentLength() = size
                override fun isOneShot() = true
                override fun writeTo(sink: BufferedSink) {
                    try { guard() } catch (failure: Exception) { throw IOException("Health disclosure invalidated", failure) }
                    val encoded = synchronized(lock) { pending.also { pending = null } }
                        ?: throw IOException("Health disclosure no longer active")
                    try { sink.write(encoded) } finally { encoded.fill(0) }
                }
            }
            val builder = Request.Builder().url(target.endpoint).post(requestBody)
            when (target.style) {
                "anthropic" -> builder.header("x-api-key", key).header("anthropic-version", "2023-06-01")
                "gemini" -> builder.header("x-goog-api-key", key)
                else -> builder.header("Authorization", "Bearer $key")
            }
            return suspendCancellableCoroutine { continuation ->
                val call = transport.newCall(builder.build())
                continuation.invokeOnCancellation { call.cancel() }
                call.enqueue(object : Callback {
                    override fun onFailure(call: Call, error: IOException) {
                        continuation.resumeWithException(error.cause?.takeIf {
                            it is HealthAccessBlocked || it is HealthWeeklyChanged || it is HealthAnalysisNoModel ||
                                it is HealthAnalysisProfileChanged || it is HealthAnalysisProfileBlocked
                        } ?: error)
                    }
                    override fun onResponse(call: Call, response: Response) {
                        val result = runCatching { response.use {
                            if (!it.isSuccessful) throw HealthAnalysisNoModel()
                            val source = it.body?.source() ?: throw HealthAnalysisInvalidReply()
                            if (source.request(MAX_RESPONSE + 1)) throw HealthAnalysisInvalidReply()
                            decode(target.style, JSONObject(source.readUtf8()))
                        } }
                        result.fold(continuation::resume, continuation::resumeWithException)
                    }
                })
            }
        } finally {
            synchronized(lock) { pending?.fill(0); pending = null }
        }
    }

    fun decode(style: String, response: JSONObject): String = when (style) {
        "anthropic" -> textParts(response.optJSONArray("content"), anthropic = true)
        "gemini" -> textParts(response.optJSONArray("candidates")?.optJSONObject(0)?.optJSONObject("content")?.optJSONArray("parts"))
        else -> response.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.let {
            if ((it.optJSONArray("tool_calls")?.length() ?: 0) != 0 || it.has("function_call")) throw HealthAnalysisInvalidReply()
            it.opt("content") as? String
        } ?: throw HealthAnalysisInvalidReply()
    }

    private fun textParts(array: JSONArray?, anthropic: Boolean = false): String = buildString {
        if (array == null || array.length() == 0) throw HealthAnalysisInvalidReply()
        for (index in 0 until array.length()) {
            val part = array.optJSONObject(index) ?: throw HealthAnalysisInvalidReply()
            if (part.has("functionCall") || part.optString("type") == "tool_use") throw HealthAnalysisInvalidReply()
            if (!part.optBoolean("thought") && (!anthropic || part.optString("type") == "text")) append(part.optString("text"))
        }
    }
    private fun message(role: String, content: String) = JSONObject().put("role", role).put("content", content)
    private fun parts(text: String) = JSONObject().put("parts", JSONArray().put(JSONObject().put("text", text)))
}
