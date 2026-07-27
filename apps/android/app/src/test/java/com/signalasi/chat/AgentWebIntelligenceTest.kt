package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.ArrayDeque

class AgentWebIntelligenceTest {
    @Test
    fun catalogExceedsEighteenSourcesAndCoversDistinctVerticals() {
        val entries = AgentWebIntelligenceEngineCatalog.entries

        assertTrue(entries.size > 18)
        assertEquals(entries.size, entries.map { it.id }.distinct().size)
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.NEWS })
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.CODE })
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.ACADEMIC })
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.COMMUNITY })
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.DOCS })
    }

    @Test
    fun nativeCatalogExposesAllTenOperationsAsLowRiskTools() {
        val service = AgentWebIntelligenceService(
            fetcher = FixedFetcher(),
            store = AgentInMemoryWebIntelligenceStore()
        )
        val definitions = AgentWebIntelligenceNativeTools.definitions(service)

        assertEquals(10, definitions.size)
        assertEquals(AgentWebIntelligenceNativeTools.toolIds, definitions.map { it.descriptor.id }.toSet())
        definitions.forEach {
            assertEquals(AgentNativeToolRisk.LOW, it.descriptor.risk)
            assertTrue("Missing web intelligence capability for ${it.descriptor.id}",
                "web_intelligence.native" in it.descriptor.capabilities)
        }
    }

    @Test
    fun encryptedCacheAndLocalExtractionRemainAvailableOffline() {
        val service = AgentWebIntelligenceService(
            fetcher = FixedFetcher(),
            store = AgentInMemoryWebIntelligenceStore()
        )
        val unavailable = AgentNativeToolAvailability(
            AgentNativeToolAvailabilityStatus.UNAVAILABLE,
            "offline"
        )
        val definitions = AgentWebIntelligenceNativeTools.definitions(service, unavailable)
            .associateBy { it.descriptor.id }

        assertEquals(
            AgentNativeToolAvailabilityStatus.UNAVAILABLE,
            definitions.getValue(AgentWebIntelligenceNativeTools.SEARCH).descriptor.availability.status
        )
        setOf(
            AgentWebIntelligenceNativeTools.EXTRACT,
            AgentWebIntelligenceNativeTools.CACHE,
            AgentWebIntelligenceNativeTools.FIND_SIMILAR,
            AgentWebIntelligenceNativeTools.WATCH
        ).forEach { id ->
            val descriptor = definitions.getValue(id).descriptor
            assertEquals(AgentNativeToolAvailabilityStatus.AVAILABLE, descriptor.availability.status)
            assertTrue(descriptor.requiredPermissions.isEmpty())
        }
    }

    @Test
    fun fusionDeduplicatesCanonicalUrlsAndExplainsRanking() {
        val fusion = AgentWebIntelligenceFusion()
        val result = fusion.fuse(
            "SignalASI agent",
            listOf(
                listOf(
                    raw("bing", 1, "SignalASI Agent", "https://www.example.test/page?utm_source=x"),
                    raw("bing", 2, "Other", "https://other.test/")
                ),
                listOf(
                    raw("duckduckgo", 1, "SignalASI Agent platform", "https://example.test/page"),
                    raw("wikipedia", 2, "SignalASI", "https://en.wikipedia.org/wiki/SignalASI")
                )
            ),
            10
        )

        assertEquals(3, result.size)
        val merged = result.first { it.url == "https://example.test/page" }
        assertEquals(setOf("bing", "duckduckgo"), merged.engineRanks.keys)
        assertTrue(merged.score.final > 0.0)
        assertTrue(merged.score.consensus > 0.0)
        assertTrue(merged.publicValue(1)["citation_id"].toString().isNotBlank())
    }

    @Test
    fun coordinatorKeepsGoodSourcesWhenAnotherSourceFails() {
        val fetcher = RoutingFetcher(
            mapOf(
                "api.github.com" to response(
                    "https://api.github.com/search/repositories",
                    "application/json",
                    """{"items":[{"full_name":"signalasi/SignalASI","html_url":"https://github.com/signalasi/SignalASI","description":"Mobile super agent","updated_at":"2026-07-27"}]}"""
                ),
                "en.wikipedia.org" to response(
                    "https://en.wikipedia.org/w/api.php",
                    "application/json",
                    """{"query":{"search":[{"pageid":7,"title":"Signal intelligence","snippet":"Evidence"}]}}"""
                )
            ),
            failures = setOf("gitlab.com")
        )
        val result = AgentWebIntelligenceSearchCoordinator(fetcher).search(
            query = "SignalASI",
            limit = 10,
            engineFanout = 3,
            requestedEngines = listOf("github", "wikipedia", "gitlab"),
            timeoutMillis = 5_000
        )

        assertEquals("partial", result.status)
        assertTrue(result.results.size >= 2)
        assertTrue(result.receipts.any { it.sourceId == "gitlab" && it.status == "failed" })
        assertTrue(result.receipts.any { it.sourceId == "github" && it.status == "completed" })
    }

    @Test
    fun searchUsesCacheWithoutRepeatingNetworkCalls() {
        var now = 10_000L
        val fetcher = FixedFetcher(
            response(
                "https://search.brave.com/search",
                "text/html",
                """<a href="https://docs.example.test/guide">SignalASI guide</a>"""
            )
        )
        val store = AgentInMemoryWebIntelligenceStore { now }
        val service = AgentWebIntelligenceService(fetcher, store, clock = { now })
        val arguments = mapOf(
            "query" to "SignalASI guide",
            "engines" to listOf("brave"),
            "engine_fanout" to 1,
            "limit" to 5
        )

        val first = service.search(arguments)
        val second = service.search(arguments)

        assertEquals(1, fetcher.calls)
        assertEquals(false, (first["cache"] as Map<*, *>)["hit"])
        assertEquals(true, (second["cache"] as Map<*, *>)["hit"])
    }

    @Test
    fun fetchCachesContentAndLocalSimilarityFindsIt() {
        var now = 20_000L
        val fetcher = FixedFetcher(
            response(
                "https://docs.example.test/agent",
                "text/plain",
                "SignalASI provides a private mobile super agent with encrypted memory."
            )
        )
        val store = AgentInMemoryWebIntelligenceStore { now }
        val service = AgentWebIntelligenceService(fetcher, store, clock = { now })

        val fetched = service.fetch(mapOf("url" to "https://docs.example.test/agent"))
        val similar = service.findSimilar(
            mapOf("query" to "encrypted mobile agent memory", "limit" to 3, "search_web" to false)
        )

        assertEquals("completed", fetched["status"])
        assertEquals(1, (similar["results"] as List<*>).size)
        val result = (similar["results"] as List<*>).first() as Map<*, *>
        assertEquals("https://docs.example.test/agent", result["url"])
        assertTrue((result["score"] as Map<*, *>)["final"] as Double > 0.5)
    }

    @Test
    fun diffReportsHashAndBoundedReadableChanges() {
        var now = 30_000L
        val fetcher = SequenceFetcher(
            response("https://status.example.test/", "text/plain", "Version one\nReady"),
            response("https://status.example.test/", "text/plain", "Version two\nReady")
        )
        val service = AgentWebIntelligenceService(
            fetcher,
            AgentInMemoryWebIntelligenceStore { now },
            clock = { now++ }
        )

        service.fetch(mapOf("url" to "https://status.example.test/"))
        val changed = service.diff(mapOf("url" to "https://status.example.test/"))
        val delta = changed["diff"] as Map<*, *>

        assertEquals(true, delta["changed"])
        assertNotEquals(delta["previous_sha256"], delta["current_sha256"])
        assertTrue(delta["summary"].toString().contains("+ Version two"))
        assertTrue(delta["summary"].toString().contains("- Version one"))
    }

    @Test
    fun watchLifecycleCreatesChecksAndRemovesPersistentWatch() {
        var now = 100_000L
        val fetcher = SequenceFetcher(
            response("https://watch.example.test/", "text/plain", "Initial"),
            response("https://watch.example.test/", "text/plain", "Changed")
        )
        val store = AgentInMemoryWebIntelligenceStore { now }
        val service = AgentWebIntelligenceService(fetcher, store, clock = { now++ })
        service.fetch(mapOf("url" to "https://watch.example.test/"))
        val created = service.watch(
            mapOf(
                "action" to "create",
                "watch_id" to "status-watch",
                "url" to "https://watch.example.test/",
                "interval_minutes" to 15
            )
        )
        assertEquals("status-watch", (created["watch"] as Map<*, *>)["watch_id"])

        val checked = service.watch(mapOf("action" to "check", "watch_id" to "status-watch"))
        val checkedRows = ((checked["metadata"] as Map<*, *>)["checked"] as List<*>)
        assertEquals(true, (checkedRows.first() as Map<*, *>)["changed"])

        val removed = service.watch(mapOf("action" to "remove", "watch_id" to "status-watch"))
        assertEquals(true, (removed["metadata"] as Map<*, *>)["removed"])
        assertFalse(store.watches().isNotEmpty())
    }

    @Test
    fun sourceHealthOpensCircuitButExplicitSourceCanProbe() {
        var now = 200_000L
        val store = AgentInMemoryWebIntelligenceStore { now }
        repeat(3) {
            store.recordSourceReceipt(
                AgentWebIntelligenceReceipt(
                    "bing", "timeout", 5_000L, 0, "engine_timeout", "timeout", true
                )
            )
            now += 1
        }
        val coordinator = AgentWebIntelligenceSearchCoordinator(
            fetcher = FixedFetcher(),
            clock = { now },
            healthProvider = { store.sourceHealth() }
        )

        assertEquals("open", store.sourceHealth().getValue("bing").circuitState(now))
        assertFalse("bing" in coordinator.selectEngines("latest news", 32, emptyList(), emptySet()))
        assertEquals(
            listOf("bing"),
            coordinator.selectEngines("latest news", 1, listOf("bing"), emptySet())
        )

        now += 60_000L
        assertEquals("half_open", store.sourceHealth().getValue("bing").circuitState(now))
        store.recordSourceReceipt(AgentWebIntelligenceReceipt("bing", "completed", 100L, 4))
        assertEquals("closed", store.sourceHealth().getValue("bing").circuitState(now))
        assertEquals(0, store.sourceHealth().getValue("bing").consecutiveFailures)
    }

    @Test
    fun sourceHealthCanBeInspectedAndResetThroughCacheTool() {
        var now = 300_000L
        val store = AgentInMemoryWebIntelligenceStore { now }
        store.recordSourceReceipt(AgentWebIntelligenceReceipt("brave", "completed", 100L, 3))
        val service = AgentWebIntelligenceService(FixedFetcher(), store, clock = { now })

        val inspected = service.cache(mapOf("action" to "source_health", "engines" to listOf("brave")))
        val rows = (inspected["metadata"] as Map<*, *>)["source_health"] as List<*>
        assertEquals(1, rows.size)
        assertEquals("brave", (rows.first() as Map<*, *>)["source_id"])

        val reset = service.cache(mapOf("action" to "reset_source_health"))
        assertEquals(1, (reset["metadata"] as Map<*, *>)["source_health_removed"])
        assertTrue(store.sourceHealth().isEmpty())
    }

    @Test
    fun cancelledReceiptDoesNotPenalizeSource() {
        val previous = AgentWebIntelligenceSourceHealth("bing", attempts = 2, successes = 2)
        val current = previous.evolve(
            AgentWebIntelligenceReceipt("bing", "cancelled", 5L, 0),
            500L
        )

        assertEquals(previous.attempts, current.attempts)
        assertEquals(previous.failures, current.failures)
        assertEquals("cancelled", current.lastStatus)
    }

    @Test
    fun fastProfileIsVisibleInSearchMetadata() {
        val service = AgentWebIntelligenceService(
            FixedFetcher(
                response(
                    "https://search.brave.com/search",
                    "text/html",
                    """<a href="https://docs.example.test/guide">SignalASI guide</a>"""
                )
            ),
            AgentInMemoryWebIntelligenceStore()
        )

        val result = service.search(
            mapOf(
                "query" to "SignalASI guide",
                "profile" to "fast",
                "engines" to listOf("brave"),
                "use_cache" to false
            )
        )
        val metadata = result["metadata"] as Map<*, *>

        assertEquals("fast", metadata["profile"])
        assertEquals("explicit_sources", metadata["source_selection"])
        assertEquals(1, (metadata["source_health"] as List<*>).size)
    }

    private fun raw(engine: String, rank: Int, title: String, url: String) =
        AgentWebIntelligenceRawResult(engine, rank, title, url, "Evidence")

    private fun response(url: String, contentType: String, body: String) =
        AgentWebIntelligenceFetched(url, contentType, body.toByteArray(), 5L)

    private class FixedFetcher(
        private val response: AgentWebIntelligenceFetched = AgentWebIntelligenceFetched(
            "https://example.test/",
            "text/plain",
            "Example".toByteArray()
        )
    ) : AgentWebIntelligenceFetcher {
        var calls = 0

        override fun fetch(
            url: String,
            maxBytes: Long,
            timeoutMillis: Long,
            cancellationToken: AgentNativeToolCancellationToken,
            checkpoint: () -> Unit
        ): AgentWebIntelligenceFetched {
            calls += 1
            checkpoint()
            return response
        }
    }

    private class RoutingFetcher(
        private val responses: Map<String, AgentWebIntelligenceFetched>,
        private val failures: Set<String> = emptySet()
    ) : AgentWebIntelligenceFetcher {
        override fun fetch(
            url: String,
            maxBytes: Long,
            timeoutMillis: Long,
            cancellationToken: AgentNativeToolCancellationToken,
            checkpoint: () -> Unit
        ): AgentWebIntelligenceFetched {
            checkpoint()
            val host = java.net.URI(url).host
            if (host in failures) throw AgentWebMediaException("source_failed", "Source failed", retryable = true)
            return responses[host] ?: error("No response for $host")
        }
    }

    private class SequenceFetcher(vararg responses: AgentWebIntelligenceFetched) : AgentWebIntelligenceFetcher {
        private val responses = ArrayDeque(responses.toList())

        override fun fetch(
            url: String,
            maxBytes: Long,
            timeoutMillis: Long,
            cancellationToken: AgentNativeToolCancellationToken,
            checkpoint: () -> Unit
        ): AgentWebIntelligenceFetched {
            checkpoint()
            return responses.removeFirst()
        }
    }
}
