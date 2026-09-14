package com.galaxyssi.watch

import com.galaxyssi.chat.AgentPublicWebSearchParser
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.time.Instant
import java.util.concurrent.TimeUnit

/** Owns all stages of one turn so Stop also cancels search and prevents the next request. */
class WatchApiOperation {
    private var cancelled = false
    private var current: Call? = null
    @Synchronized fun attach(call: Call): Call {
        if (cancelled) { call.cancel(); throw IOException("Cancelled") }
        current = call
        return call
    }
    @Synchronized fun cancel() { cancelled = true; current?.cancel() }
    @Synchronized fun checkActive() { if (cancelled) throw IOException("Cancelled") }
}

internal data class WatchWebEvidence(val hits: List<AgentPublicWebSearchParser.Hit>, val retrievedAt: String) {
    fun json(): String = JSONObject().put("retrieved_at", retrievedAt).put("sources", JSONArray().apply {
        hits.forEachIndexed { index, hit -> put(JSONObject().put("id", index + 1)
            .put("title", hit.title).put("url", hit.url).put("search_excerpt", hit.excerpt)) }
    }).toString()
    fun sources(): String = hits.mapIndexed { index, hit -> "[${index + 1}] ${hit.title}\n${hit.url}" }.joinToString("\n")
}

/** Public search excerpts only; never sends API credentials or conversation history to engines. */
internal class WatchWebSearch(private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(6, TimeUnit.SECONDS).readTimeout(8, TimeUnit.SECONDS).callTimeout(12, TimeUnit.SECONDS)
    .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build(),
    private val engines: List<Pair<String, String>> = listOf(
        "https://cn.bing.com/search" to "q", "https://www.baidu.com/s" to "wd",
        "https://html.duckduckgo.com/html/" to "q")) {
    fun search(prompt: String, operation: WatchApiOperation): WatchWebEvidence {
        val query = prompt.trim().take(500)
        require(query.isNotBlank())
        for ((endpoint, parameter) in engines) {
            operation.checkActive()
            val result = runCatching {
                val url = endpoint.toHttpUrl().newBuilder().addQueryParameter(parameter, query).build()
                val request = Request.Builder().url(url)
                    .header("User-Agent", "Mozilla/5.0 (Android 13) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36")
                    .header("Accept-Language", java.util.Locale.getDefault().toLanguageTag()).build()
                operation.attach(client.newCall(request)).execute().use { response ->
                    require(response.isSuccessful)
                    val body = response.body ?: error("Empty search response")
                    val bytes = body.byteStream().use { it.readNBytes(512_001) }
                    require(bytes.size <= 512_000)
                    AgentPublicWebSearchParser.parse(String(bytes, body.contentType()?.charset(Charsets.UTF_8) ?: Charsets.UTF_8), url.toString(), 4)
                        .filter { it.excerpt.isNotBlank() }
                }
            }.getOrNull()
            operation.checkActive()
            if (!result.isNullOrEmpty()) return WatchWebEvidence(result, Instant.now().toString())
        }
        throw ApiFailure(R.string.web_search_failed)
    }
}
