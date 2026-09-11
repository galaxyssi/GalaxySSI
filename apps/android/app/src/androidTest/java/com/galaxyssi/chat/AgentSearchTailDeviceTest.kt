package com.galaxyssi.chat

import android.os.Build
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class AgentSearchTailDeviceTest {
    @Test fun publicResultRepresentation() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_search_tail") == "true")
        assertEquals("SM-S9480", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val delegate = AgentBoundedWebIntelligenceFetcher(AgentBoundedWebService(AgentPinnedOkHttpWebTransport()))
        val reports = JSONArray()
        for (id in listOf("baidu", "sogou")) {
            val fetcher = object : AgentWebIntelligenceFetcher by delegate, AgentWebIntelligenceRequestFetcher {
                override fun fetch(url: String, maxBytes: Long, timeoutMillis: Long, headers: Map<String, String>,
                    cancellationToken: AgentNativeToolCancellationToken, checkpoint: () -> Unit): AgentWebIntelligenceFetched {
                    val fetched = delegate.fetch(url, maxBytes, timeoutMillis, headers, cancellationToken, checkpoint)
                    File(context.getExternalFilesDir("reports"), "$id-public-result.html").writeBytes(fetched.body)
                    reports.put(JSONObject().put("engine", id).put("headers", JSONObject(headers))
                        .put("url", fetched.url).put("content_type", fetched.contentType)
                        .put("bytes", fetched.body.size).put("duration_ms", fetched.durationMillis))
                    return fetched
                }
            }
            val adapter = AgentWebIntelligenceSearchAdapter(AgentWebIntelligenceEngineCatalog.entries.single { it.id == id }, fetcher)
            val result = runCatching { adapter.search("花仙鱼 是什么鱼 学名", 8, 6_000, AgentNativeToolCancellationToken.NONE) {} }
            if (reports.length() > 0 && reports.getJSONObject(reports.length() - 1).optString("engine") == id) {
                reports.getJSONObject(reports.length() - 1).put("hits", result.getOrNull()?.size ?: 0)
                    .put("error_code", (result.exceptionOrNull() as? AgentWebMediaException)?.code.orEmpty())
            }
            File(context.getExternalFilesDir("reports"), "public-result-representation.json").writeText(reports.toString(2))
        }
    }

    @Test fun recentUiSearchTimings() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_search_tail") == "true")
        assertEquals("SM-S9480", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val uiFile = File(context.getExternalFilesDir("reports"), "image-ui-latest.json")
        val ui = JSONObject(uiFile.readText())
        val start = InstrumentationRegistry.getArguments().getString("since_millis")?.toLongOrNull()
            ?: (uiFile.lastModified() - ui.getLong("elapsed_ms") - 10_000L)
        val database = AgentEncryptedDatabase(context, "galaxyssi-web-intelligence-v1")
        val rows = JSONArray()
        database.recentKeys("search:", 16).forEach { key ->
            val response = JSONObject(database.readString(key, "{}")).optJSONObject("response") ?: return@forEach
            val cache = response.optJSONObject("cache") ?: return@forEach
            if (cache.optLong("expires_at_millis") - AgentWebIntelligenceService.DEFAULT_CACHE_TTL_MILLIS < start) return@forEach
            rows.put(JSONObject().put("query", response.optString("query"))
                .put("metadata", response.optJSONObject("metadata"))
                .put("receipts", response.optJSONArray("receipts")))
        }
        File(context.getExternalFilesDir("reports"), "image-ui-search-timings.json").writeText(rows.toString(2))
    }

    @Test fun publicSourceTimingMatrix() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_search_tail") == "true")
        assertEquals("SM-S9480", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val service = AgentWebIntelligenceService.android(context,
            AgentBoundedWebService(AgentPinnedOkHttpWebTransport()))
        val cases = listOf(
            mapOf("query" to "花仙鱼 是什么鱼 图片", "profile" to "fast", "limit" to 6),
            mapOf("query" to "花仙鱼 是什么鱼 学名", "profile" to "fast", "limit" to 6),
            mapOf("query" to "花仙鱼 学名", "profile" to "fast", "limit" to 6),
            mapOf("query" to "花仙鱼 学名", "profile" to "balanced", "limit" to 6),
            mapOf("query" to "花仙鱼 学名", "profile" to "fast", "limit" to 6,
                "engines" to listOf("baidu", "sogou", "bing", "duckduckgo"), "engine_fanout" to 4),
            mapOf("query" to "七龙珠 飞船 内部 图片", "profile" to "fast", "limit" to 6,
                "verticals" to listOf("image"), "engine_fanout" to 3),
            mapOf("query" to "Android WebView 多进程", "profile" to "fast", "limit" to 6)
        )
        val reports = JSONArray()
        val report = File(context.getExternalFilesDir("reports"), "search-tail-latest.json")
        for (arguments in cases) {
            val effective = if (arguments["verticals"] == listOf("image")) arguments else
                CloudWebGrounding.normalizeArguments("web_search", JSONObject(AgentNativeJsonCodec.stringify(arguments)))
            val started = SystemClock.elapsedRealtime()
            val output = service.invoke("search", effective + ("use_cache" to false))
            assertEquals(false, (output["cache"] as? Map<*, *>)?.get("hit"))
            reports.put(JSONObject().put("request", JSONObject(AgentNativeJsonCodec.stringify(effective)))
                .put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                .put("response", JSONObject(AgentNativeJsonCodec.stringify(output))))
            report.writeText(reports.toString(2))
        }
    }
}
