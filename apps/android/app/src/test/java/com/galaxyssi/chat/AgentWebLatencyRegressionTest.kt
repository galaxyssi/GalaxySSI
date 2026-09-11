package com.galaxyssi.chat

import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.net.URI

class AgentWebLatencyRegressionTest {
    @Test fun searchUsesRawFetcherAndArticleKeepsDynamicFetcher() {
        val articles = PageFetcher()
        val searches = PageFetcher()
        val service = AgentWebIntelligenceService(articles, AgentInMemoryWebIntelligenceStore(), searchFetcher = searches)
        service.search(mapOf("query" to "test", "engines" to listOf("brave"), "use_cache" to false))
        assertEquals(0, articles.calls)
        assertTrue(searches.calls > 0)
        val searchCalls = searches.calls
        service.fetch(mapOf("url" to "https://article.test/a"))
        assertEquals(1, articles.calls)
        assertEquals(searchCalls, searches.calls)
    }

    @Test fun canonicalUrlsPreserveEscapedComponentsAndAreIdempotent() {
        val url = "https://www.example.test/a%2Fb/%E4%B8%AD?q=%E5%B0%8F%20fish&x=%25%26%3D%2B&utm_source=test#fragment"
        val canonical = AgentWebIntelligenceText.canonicalUrl(url)
        assertEquals("https://example.test/a%2Fb/%E4%B8%AD?q=%E5%B0%8F%20fish&x=%25%26%3D%2B", canonical)
        assertEquals(canonical, AgentWebIntelligenceText.canonicalUrl(canonical))
        assertEquals(URI(url).rawPath, URI(canonical).rawPath)
        assertEquals("https://example.test/", AgentWebIntelligenceText.canonicalUrl("https://example.test"))
        val pack = AgentWebEvidencePack.build("encoded source", "completed", emptyList(),
            listOf(mapOf("url" to url, "title" to "Source", "excerpt" to "Evidence")), emptyList(), 0L)
        assertTrue(AgentWebEvidenceVerification.validateAnswerPacks("[Source]($canonical)", listOf(pack)).valid)
    }

    @Test fun fetchAndCacheGetDoNotScanTheStoreForStats() {
        val store = object : AgentWebIntelligenceStore by AgentInMemoryWebIntelligenceStore() {
            override fun stats(): AgentNativeJsonObject = error("Full stats entered the request path")
            override fun documents(): List<AgentWebIntelligenceDocument> = error("Full document scan")
        }
        val service = AgentWebIntelligenceService(PageFetcher(), store)
        val url = "https://latency.example.test/article"
        assertEquals("completed", service.invoke("fetch", mapOf("url" to url))["status"])
        assertEquals("completed", service.invoke("cache", mapOf("action" to "get", "url" to url))["status"])
    }

    @Test fun invalidEngineAnywhereInPlanFailsBeforeStorageOrNetwork() {
        val store = object : AgentWebIntelligenceStore by AgentInMemoryWebIntelligenceStore() {
            override fun getSearch(key: String): AgentNativeJsonObject? = error("Cache accessed before validation")
            override fun learnedSources(): List<AgentWebIntelligenceLearnedSource> = error("Learning accessed before validation")
        }
        val fetcher = PageFetcher()
        val service = AgentWebIntelligenceService(fetcher, store)
        val error = assertThrows(IllegalArgumentException::class.java) {
            service.invoke("research", mapOf("query" to "test", "query_plan" to listOf(
                mapOf("query" to "valid", "engines" to listOf("brave")),
                mapOf("query" to "invalid", "engines" to listOf("wiktionary")))))
        }
        assertTrue(error.message!!.contains("wiktionary"))
        assertEquals(0, fetcher.calls)
        assertThrows(IllegalArgumentException::class.java) {
            service.search(mapOf("query" to "test", "engines" to listOf("wiktionary")))
        }
    }

    @Test fun imagesFromSameSourceSurvivePackingAndCompaction() {
        val source = "https://example.test/source"
        val pack = AgentWebEvidencePack.build("images", "completed", emptyList(),
            (1..3).map { index -> mapOf("url" to source, "title" to "Images", "excerpt" to "x".repeat(30_000),
                "image_url" to "https://cdn.example.test/$index.jpg", "image_width" to 800, "image_height" to 600) },
            emptyList(), 0)
        val item = (pack["items"] as List<*>).single() as Map<*, *>
        assertEquals(3, (item["images"] as List<*>).size)
        val huge = pack + mapOf("padding" to "x".repeat(30_000))
        val encoded = CloudWebGrounding.boundedModelJson(mapOf("operation" to "search", "evidence_pack" to huge))
        assertTrue(encoded.length <= 24_000)
        assertEquals(3, JSONObject(encoded).getJSONObject("evidence_pack").getJSONArray("items")
            .getJSONObject(0).getJSONArray("images").length())
        assertTrue(AgentWebEvidenceVerification.validateAnswerPacks(
            "![Image](https://cdn.example.test/1.jpg) [Source]($source)", listOf(pack)).valid)
        assertFalse(AgentWebEvidenceVerification.validateAnswerPacks(
            "![Invented](https://cdn.example.test/invented.jpg) [Source]($source)", listOf(pack)).valid)
        assertFalse(AgentWebEvidenceVerification.validateAnswerPacks(
            "[Not a source](https://cdn.example.test/1.jpg)", listOf(pack)).valid)
    }

    @Test fun nonWebImageAddressesAreNotExposed() {
        val pack = AgentWebEvidencePack.build("images", "completed", emptyList(),
            listOf(mapOf("url" to "https://example.test", "image_url" to "file:///private/key")), emptyList(), 0)
        val item = (pack["items"] as List<*>).single() as Map<*, *>
        assertTrue((item["images"] as List<*>).isEmpty())
    }

    @Test fun repeatedEvidenceAndDifferentFailedQueriesStopWithoutCallCountLimit() {
        val progress = CloudWebToolLoopProgress()
        val evidence = """{"evidence_pack":{"items":[{"url":"https://example.test","content_sha256":"abc","evidence_level":"retrieved_body"}]}}"""
        assertFalse(progress.observeEvidenceBatch(listOf(evidence)))
        assertFalse(progress.observeEvidenceBatch(listOf(evidence)))
        assertFalse(progress.observeEvidenceBatch(listOf("""{"status":"failed","query":"new"}""")))
        assertTrue(progress.observeEvidenceBatch(listOf(evidence)))
        assertFalse(progress.observeEvidenceBatch(listOf(evidence.replace("abc", "updated"))))
    }

    @Test fun deadlineIsSharedAndMonotonic() {
        var nanos = 0L
        val budget = AgentWebExecutionBudget(1_000) { nanos }
        assertEquals(1_000L, budget.remainingMillis)
        nanos = 700_000_000L
        assertEquals(300L, budget.remainingMillis)
        nanos = 1_000_000_000L
        assertTrue(budget.expired)
    }

    @Test fun researchQueriesShareOneDeadlineAndPreservePartialEvidence() {
        val fetcher = object : AgentWebIntelligenceFetcher {
            override fun fetch(url: String, maxBytes: Long, timeoutMillis: Long,
                cancellationToken: AgentNativeToolCancellationToken, checkpoint: () -> Unit): AgentWebIntelligenceFetched {
                Thread.sleep(1_150)
                return AgentWebIntelligenceFetched(url, "text/html",
                    "<a href=\"https://partial.example.test/evidence\">Partial evidence</a>".toByteArray())
            }
        }
        val service = AgentWebIntelligenceService(fetcher, AgentInMemoryWebIntelligenceStore())
        val started = System.nanoTime()
        val result = service.invoke("research", mapOf("query" to "public test", "timeout_ms" to 2_000L,
            "engines" to listOf("brave"), "query_plan" to (1..5).map { mapOf("query" to "evidence $it") }))
        assertTrue("Plan multiplied its deadline", (System.nanoTime() - started) / 1_000_000L < 3_500L)
        assertEquals(1, (result["metadata"] as Map<*, *>)["queries_executed"])
        assertEquals("partial", result["status"])
        assertTrue((result["results"] as List<*>).isNotEmpty())
    }

    @Test fun veryLongMediaUrlsStillRespectModelPayloadLimit() {
        val source = "https://example.test/" + "s".repeat(3_900)
        val pack = AgentWebEvidencePack.build("images", "completed", emptyList(), (1..3).map {
            mapOf("url" to source, "image_url" to "https://cdn.example.test/$it/" + "a".repeat(3_900),
                "thumbnail_url" to "https://cdn.example.test/thumb/$it/" + "b".repeat(3_900))
        }, emptyList(), 0)
        val encoded = CloudWebGrounding.boundedModelJson(mapOf("operation" to "search", "evidence_pack" to pack))
        assertTrue("Model output was ${encoded.length} characters", encoded.length <= 24_000)
        assertTrue(JSONObject(encoded).getJSONObject("evidence_pack").getJSONArray("items")
            .getJSONObject(0).getJSONArray("images").length() > 0)
    }

    @Test fun deadlineCancelsTheActualBlockingTransport() = runBlocking {
        val stopped = CountDownLatch(1)
        val budget = AgentWebExecutionBudget(150)
        budget.execute { token, _ ->
            val registration = token.invokeOnCancellation { stopped.countDown() }
            try { assertTrue(stopped.await(2, TimeUnit.SECONDS)) } finally { registration.dispose() }
        }
        assertTrue(budget.expired)
    }

    @Test fun parentCancellationClosesTransportWithoutWaitingForDeadline() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val stopped = CountDownLatch(1)
        val job = launch {
            AgentWebExecutionBudget(60_000).execute { token, _ ->
                val registration = token.invokeOnCancellation { stopped.countDown() }
                entered.complete(Unit)
                try { stopped.await(2, TimeUnit.SECONDS) } finally { registration.dispose() }
            }
        }
        entered.await()
        job.cancelAndJoin()
        assertTrue(stopped.await(1, TimeUnit.SECONDS))
    }

    private class PageFetcher : AgentWebIntelligenceFetcher {
        var calls = 0
        override fun fetch(url: String, maxBytes: Long, timeoutMillis: Long,
            cancellationToken: AgentNativeToolCancellationToken, checkpoint: () -> Unit): AgentWebIntelligenceFetched {
            calls++
            checkpoint()
            return AgentWebIntelligenceFetched(url, "text/html", "<html><body><article>${"Evidence text. ".repeat(100)}</article></body></html>".toByteArray())
        }
    }
}
