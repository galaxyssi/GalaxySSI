package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class AgentWebIntelligenceTest {
    @Test
    fun catalogExceedsEighteenSourcesAndCoversDistinctVerticals() {
        val entries = AgentWebIntelligenceEngineCatalog.entries

        assertEquals(287, entries.size)
        assertEquals(entries.size, entries.map { it.id }.distinct().size)
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.NEWS })
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.CODE })
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.ACADEMIC })
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.COMMUNITY })
        assertTrue(entries.any { it.vertical == AgentWebIntelligenceVertical.DOCS })
        assertTrue(
            setOf(
                "bing", "bing_news", "brave", "brave_image", "duckduckgo",
                "duckduckgo_image", "mojeek", "marginalia", "wikipedia",
                "stackoverflow", "hacker_news", "lobsters", "github_code",
                "devdocs", "mdn", "arxiv", "semantic_scholar", "crates_io"
            ).all { expected -> entries.any { it.id == expected } }
        )
        val counts = entries.filter(AgentWebIntelligenceEngineSpec::enabledByDefault)
            .groupingBy(AgentWebIntelligenceEngineSpec::vertical)
            .eachCount()
        AgentWebIntelligenceVertical.entries
            .filterNot { it == AgentWebIntelligenceVertical.LOCAL }
            .forEach { vertical ->
                assertTrue(
                    "${vertical.wireValue} must expose five to ten sources",
                    counts.getOrDefault(vertical, 0) in 5..10
                )
            }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(entries.map { it.id }.sorted().joinToString("\n").toByteArray())
            .joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
        assertEquals(
            "ebe2e39787edab5166db322b0322e1440ccc733a150db5375443e6bd721f56a9",
            digest
        )
    }

    @Test
    fun wigoloGapSourcesUseNativeAdaptersAndPreserveImageMetadata() {
        val fetcher = WigoloFetcher()
        val coordinator = AgentWebIntelligenceSearchCoordinator(
            fetcher = fetcher,
            credentialProvider = AgentWebIntelligenceCredentialProvider { key ->
                if (key == AgentEncryptedWebIntelligenceCredentials.BRAVE_API_KEY) {
                    "brave-secret"
                } else {
                    ""
                }
            }
        )

        val result = coordinator.search(
            query = "React SignalASI image code",
            limit = 10,
            engineFanout = 5,
            requestedEngines = listOf(
                "brave_image",
                "duckduckgo_image",
                "marginalia",
                "devdocs",
                "github_code"
            ),
            timeoutMillis = 5_000L
        )

        assertEquals("completed", result.status)
        val engines = result.results.flatMap { it.engineRanks.keys }.toSet()
        assertTrue(
            setOf(
                "brave_image",
                "duckduckgo_image",
                "marginalia",
                "devdocs",
                "github_code"
            ).all(engines::contains)
        )
        val image = result.results.first { it.vertical == AgentWebIntelligenceVertical.IMAGE }
        val public = image.publicValue(1)
        assertTrue(public["image_url"].toString().startsWith("https://cdn.example.test/"))
        assertTrue((public["image_width"] as Int) > 0)
        assertTrue(fetcher.requests.any {
            it.url.contains("api.search.brave.com") &&
                it.headers["X-Subscription-Token"] == "brave-secret"
        })
        assertTrue(fetcher.requests.any {
            it.url.contains("duckduckgo.com/i.js") &&
                it.headers.containsKey("Referer")
        })
    }

    @Test
    fun braveImageIsSkippedWithoutCredentialDuringAdaptiveRouting() {
        val coordinator = AgentWebIntelligenceSearchCoordinator(FixedFetcher())

        val engines = coordinator.selectEngines(
            query = "SignalASI images",
            fanout = 32,
            requested = emptyList(),
            verticals = setOf(AgentWebIntelligenceVertical.IMAGE)
        )

        assertFalse("brave_image" in engines)
        assertTrue("duckduckgo_image" in engines)
    }

    @Test
    fun indexedSourceRejectsResultsOutsideItsDeclaredDomain() {
        val coordinator = AgentWebIntelligenceSearchCoordinator(
            FixedFetcher(
                response(
                    "https://html.duckduckgo.com/html/?q=travel",
                    "text/html",
                    """
                    <a href="https://www.tripadvisor.com/Hotel_Review-test">Trusted result</a>
                    <a href="https://attacker.example/fake">Injected result</a>
                    """.trimIndent()
                )
            )
        )

        val result = coordinator.search(
            query = "Shanghai hotel",
            requestedEngines = listOf("tripadvisor"),
            engineFanout = 1
        )

        assertEquals(1, result.results.size)
        assertEquals(
            "tripadvisor.com",
            java.net.URI(result.results.single().url).host.removePrefix("www.")
        )
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
        val research = definitions.first { it.descriptor.id == AgentWebIntelligenceNativeTools.RESEARCH }
        val properties = research.descriptor.inputSchema.document["properties"] as Map<*, *>
        assertTrue(
            setOf(
                "query_plan", "profile", "engines", "verticals", "categories", "use_cache",
                "page_read_parallelism", "per_host_parallelism", "page_read_timeout_ms",
                "early_complete"
            ).all(properties::containsKey)
        )
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
    fun redirectedFetchCachesUnderTheRequestedUrl() {
        val requestedUrl = "https://docs.example.test/article"
        val resolvedUrl = "$requestedUrl?redirected=1"
        val fetcher = FixedFetcher(
            response(resolvedUrl, "text/plain", "Redirected article content")
        )
        val service = AgentWebIntelligenceService(fetcher, AgentInMemoryWebIntelligenceStore())

        val first = service.fetch(mapOf("url" to requestedUrl))
        val second = service.fetch(mapOf("url" to requestedUrl))
        val document = (second["documents"] as List<*>).single() as Map<*, *>
        val metadata = document["metadata"] as Map<*, *>

        assertEquals(1, fetcher.calls)
        assertEquals(false, (first["cache"] as Map<*, *>)["hit"])
        assertEquals(true, (second["cache"] as Map<*, *>)["hit"])
        assertEquals(requestedUrl, document["url"])
        assertEquals(resolvedUrl, metadata["resolved_url"])
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

    @Test
    fun balancedSearchCanFinishAfterCollectingSufficientDiverseEvidence() {
        val groups = (0 until 4).map { source ->
            (0 until 3).map { index ->
                raw(
                    engine = "engine-$source",
                    rank = index + 1,
                    title = "Evidence $source-$index",
                    url = "https://source-$source-$index.example/evidence"
                )
            }
        }

        assertTrue(
            AgentWebSearchCompletionPolicy.hasSufficientEvidence(
                profile = AgentWebIntelligenceSearchProfile.BALANCED.wireValue,
                explicitSources = false,
                groups = groups,
                limit = 6
            )
        )
        assertFalse(
            AgentWebSearchCompletionPolicy.hasSufficientEvidence(
                profile = AgentWebIntelligenceSearchProfile.BALANCED.wireValue,
                explicitSources = true,
                groups = groups,
                limit = 6
            )
        )
        assertFalse(
            AgentWebSearchCompletionPolicy.hasSufficientEvidence(
                profile = AgentWebIntelligenceSearchProfile.DEEP.wireValue,
                explicitSources = false,
                groups = groups,
                limit = 6
            )
        )
    }

    @Test
    fun researchReadsRankedPagesInParallelWithHostLimitsAndFailureIsolation() {
        val fetcher = ParallelResearchFetcher()
        val service = AgentWebIntelligenceService(
            fetcher = fetcher,
            store = AgentInMemoryWebIntelligenceStore()
        )

        val result = service.research(
            mapOf(
                "query" to "SignalASI parallel evidence",
                "evidence_limit" to 6,
                "profile" to "fast",
                "engines" to listOf("brave"),
                "engine_fanout" to 1,
                "use_cache" to false,
                "timeout_ms" to 5_000L,
                "page_read_parallelism" to 6,
                "per_host_parallelism" to 1,
                "page_read_timeout_ms" to 5_000L,
                "early_complete" to true
            )
        )

        val metadata = result["metadata"] as Map<*, *>
        val documents = result["documents"] as List<*>
        val receipts = (result["receipts"] as List<*>).filterIsInstance<Map<*, *>>()
        assertEquals("completed", result["status"])
        assertTrue("expected at least three concurrent page reads", fetcher.maxActive.get() >= 3)
        assertTrue("same-host page reads must remain serialized", fetcher.maxPerHost.get() <= 1)
        assertTrue(documents.size >= 4)
        assertEquals(true, metadata["page_read_sufficient"])
        assertEquals(true, metadata["page_read_early_completed"])
        assertEquals("sufficient_diverse_evidence", metadata["page_read_completion_reason"])
        assertTrue((metadata["page_read_domains"] as Int) >= 3)
        assertTrue(receipts.any { it["error_code"] == "source_failed" })
        assertTrue(receipts.any { it["status"] == "cancelled" })
    }

    @Test
    fun evidenceReaderUsesOneSharedDeadlineForAllPendingPages() {
        val results = (1..6).map { index ->
            linkedMapOf<String, Any?>("url" to "https://deadline-$index.example.test/evidence")
        }
        val started = System.nanoTime()

        val batch = readAgentWebEvidence(
            results = results,
            evidenceLimit = 6,
            parallelism = 2,
            perHostParallelism = 1,
            timeoutMillis = 150L,
            earlyComplete = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            checkpoint = {}
        ) { url, _, cancellationToken, checkpoint ->
            repeat(200) {
                checkpoint()
                if (cancellationToken.isCancellationRequested) throw AgentNativeToolCancelledException()
                Thread.sleep(10L)
            }
            AgentWebEvidenceFetchedDocument(
                document = testDocument(url, "late evidence".repeat(100)),
                receipt = AgentWebIntelligenceReceipt("public_https", "completed", 2_000L, 1)
            )
        }

        val elapsedMillis = java.util.concurrent.TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
        assertEquals("shared_deadline", batch.completionReason)
        assertEquals(6, batch.candidateCount)
        assertEquals(0, batch.documents.size)
        assertTrue("shared deadline should not become a per-page timeout", elapsedMillis < 1_000L)
        assertTrue(batch.receipts.all { it["error_code"] == "shared_deadline" })
    }

    @Test
    fun evidenceReaderPreservesSearchRankWhenPagesFinishOutOfOrder() {
        val results = (1..4).map { index ->
            linkedMapOf<String, Any?>("url" to "https://rank-$index.example.test/evidence")
        }

        val batch = readAgentWebEvidence(
            results = results,
            evidenceLimit = 4,
            parallelism = 4,
            perHostParallelism = 1,
            timeoutMillis = 2_000L,
            earlyComplete = false,
            cancellationToken = AgentNativeToolCancellationToken.NONE,
            checkpoint = {}
        ) { url, _, _, _ ->
            val rank = Regex("rank-(\\d+)").find(url)?.groupValues?.get(1)?.toLong() ?: 1L
            Thread.sleep((5L - rank) * 20L)
            AgentWebEvidenceFetchedDocument(
                document = testDocument(url, "ranked evidence ".repeat(100)),
                receipt = AgentWebIntelligenceReceipt("public_https", "completed", 100L, 1)
            )
        }

        assertEquals(results.map { it["url"] }, batch.documents.map { it.url })
        assertEquals("evidence_limit_reached", batch.completionReason)
    }

    @Test
    fun explicitUrlPrefetchPopulatesTheSameCacheUsedByWebFetch() {
        val fetcher = CountingPageFetcher()
        val store = AgentInMemoryWebIntelligenceStore()
        val prefetchService = AgentWebIntelligenceService(fetcher, store)
        val toolService = AgentWebIntelligenceService(fetcher, store)
        val url = "https://prefetch.example.test/article"

        val prefetched = prefetchService.prefetchDocuments(listOf(url))
        val fetched = toolService.fetch(mapOf("url" to url))

        assertEquals(1, prefetched.documents.size)
        assertEquals(1, fetcher.calls.get())
        assertEquals(true, (fetched["cache"] as Map<*, *>)["hit"])
        val receipt = (fetched["receipts"] as List<*>).single() as Map<*, *>
        assertEquals("local_cache", receipt["source_id"])
    }

    @Test
    fun explicitUrlPrefetchPreservesItsFullRequestTimeoutBudget() {
        val fetcher = CountingPageFetcher()
        val service = AgentWebIntelligenceService(fetcher, AgentInMemoryWebIntelligenceStore())

        val prefetched = service.prefetchDocuments(
            urls = listOf("https://timeout.example.test/article"),
            timeoutMillis = 30_000L
        )

        assertEquals(1, prefetched.documents.size)
        assertTrue(fetcher.lastTimeoutMillis.get() >= 29_000L)
    }

    @Test
    fun invokedFetchReturnsCompactUnifiedEvidencePack() {
        val paragraph = "Retrieved article evidence for unified model synthesis. ".repeat(80)
        val service = AgentWebIntelligenceService(
            FixedFetcher(
                AgentWebIntelligenceFetched(
                    "https://www.example.test/report?utm_source=test",
                    "text/html",
                    "<html><head><title>Unified report</title></head><body><article>$paragraph</article></body></html>"
                        .toByteArray()
                )
            ),
            AgentInMemoryWebIntelligenceStore()
        )

        val response = service.invoke("fetch", mapOf("url" to "https://example.test/report"))
        val pack = response["evidence_pack"] as Map<*, *>
        val document = (response["documents"] as List<*>).single() as Map<*, *>
        val item = (pack["items"] as List<*>).single() as Map<*, *>

        assertEquals(AGENT_WEB_EVIDENCE_PACK_PROTOCOL, pack["protocol"])
        assertFalse(document.containsKey("content"))
        assertEquals("document", item["source_kind"])
        assertEquals("retrieved_body", item["evidence_level"])
        assertEquals("https://example.test/report", item["url"])
        assertTrue(item["citation_id"].toString().isNotBlank())
        assertTrue(item["content_sha256"].toString().matches(Regex("[a-f0-9]{64}")))
        assertTrue(item["excerpt"].toString().contains("Retrieved article evidence"))
    }

    @Test
    fun evidencePackPrefersRetrievedBodyOverDuplicateDiscoveryResult() {
        val content = "Complete retrieved body with verified details. ".repeat(40)
        val document = testDocument("https://www.example.test/report?utm_source=search", content)
            .publicValue()
        val result = linkedMapOf<String, Any?>(
            "url" to "https://example.test/report",
            "title" to "Search result",
            "excerpt" to "Short discovery snippet",
            "engines" to listOf("bing")
        )

        val pack = AgentWebEvidencePack.build(
            query = "report",
            status = "completed",
            documents = listOf(document),
            results = listOf(result),
            receipts = emptyList(),
            generatedAtMillis = 123L
        )
        val items = pack["items"] as List<*>
        val item = items.single() as Map<*, *>

        assertEquals(1, items.size)
        assertEquals("document", item["source_kind"])
        assertTrue(item["excerpt"].toString().startsWith("Complete retrieved body"))
    }

    @Test
    fun evidencePackCitationMatchesTheCrossPlatformFixture() {
        val document = linkedMapOf<String, Any?>(
            "url" to "https://www.example.com/a?utm_source=x&b=2&a=1",
            "title" to "Fixture",
            "content" to "Fixture evidence",
            "content_sha256" to "a".repeat(64)
        )

        val pack = AgentWebEvidencePack.build(
            query = "fixture",
            status = "completed",
            documents = listOf(document),
            results = emptyList(),
            receipts = emptyList(),
            generatedAtMillis = 1L
        )
        val item = (pack["items"] as List<*>).single() as Map<*, *>

        assertEquals("https://example.com/a?a=1&b=2", item["url"])
        assertEquals("2a6252e1a64266545ebcf887", item["citation_id"])
    }

    @Test
    fun concurrentServiceFetchesShareOneNetworkDownload() {
        val fetcher = CountingPageFetcher(delayMillis = 250L)
        val store = AgentInMemoryWebIntelligenceStore()
        val firstService = AgentWebIntelligenceService(fetcher, store)
        val secondService = AgentWebIntelligenceService(fetcher, store)
        val url = "https://single-flight.example.test/article"
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val first = executor.submit<AgentNativeJsonObject> {
                start.await()
                firstService.fetch(mapOf("url" to url))
            }
            val second = executor.submit<AgentNativeJsonObject> {
                start.await()
                secondService.fetch(mapOf("url" to url))
            }
            start.countDown()
            val responses = listOf(
                first.get(3, TimeUnit.SECONDS),
                second.get(3, TimeUnit.SECONDS)
            )

            assertEquals(1, fetcher.calls.get())
            assertEquals(1, responses.count { (it["cache"] as Map<*, *>)["hit"] == true })
            val sources = responses.flatMap { response ->
                (response["receipts"] as List<*>).filterIsInstance<Map<*, *>>()
                    .map { it["source_id"] }
            }
            assertTrue(sources.any { it == "shared_fetch_cache" || it == "local_cache" })
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun repeatedIndependentEvidencePromotesARestrictedLearnedSource() {
        val store = AgentInMemoryWebIntelligenceStore { 500_000L }
        val result = AgentWebIntelligenceResult(
            title = "Independent travel guide",
            url = "https://independent-travel.example/shanghai",
            excerpt = "A current destination guide",
            publishedAt = "",
            vertical = AgentWebIntelligenceVertical.TRAVEL
        )

        store.observeSourceCandidates("Shanghai hotel guide", setOf("travel"), listOf(result))
        store.observeSourceCandidates("Shanghai visitor itinerary", setOf("travel"), listOf(result))
        store.observeSourceCandidates("Shanghai hotel guide", setOf("travel"), listOf(result))

        val learned = store.learnedSources().single()
        assertEquals("verified", learned.status)
        assertEquals(3, learned.observations)
        assertEquals(2, learned.queryFingerprints.size)
        assertEquals(setOf("independent-travel.example"), learned.toEngineSpec(0).allowedHosts)

        val coordinator = AgentWebIntelligenceSearchCoordinator(
            fetcher = FixedFetcher(),
            learnedSourceProvider = store::learnedSources
        )
        assertTrue(
            learned.sourceId in coordinator.selectEngines(
                query = "Shanghai travel",
                fanout = 32,
                requested = emptyList(),
                verticals = setOf(AgentWebIntelligenceVertical.TRAVEL)
            )
        )
    }

    @Test
    fun learnedCategoryTagsCanGrowBeyondTheBuiltInTaxonomy() {
        val store = AgentInMemoryWebIntelligenceStore { 600_000L }
        val result = AgentWebIntelligenceResult(
            title = "Robotics field notes",
            url = "https://robotics-field-notes.example/latest",
            excerpt = "Independent robotics engineering evidence",
            publishedAt = "",
            vertical = AgentWebIntelligenceVertical.TECHNOLOGY
        )
        store.observeSourceCandidates("robot motion planning", setOf("robotics"), listOf(result))
        store.observeSourceCandidates("robot actuator guide", setOf("robotics"), listOf(result))
        store.observeSourceCandidates("robot motion planning", setOf("robotics"), listOf(result))

        val learned = store.learnedSources().single()
        val coordinator = AgentWebIntelligenceSearchCoordinator(
            fetcher = FixedFetcher(),
            learnedSourceProvider = store::learnedSources
        )

        assertEquals("verified", learned.status)
        assertTrue("robotics" in learned.categoryTags)
        assertEquals(
            learned.sourceId,
            coordinator.selectEngines(
                query = "specialized field notes",
                fanout = 1,
                requested = emptyList(),
                verticals = emptySet(),
                categoryTags = setOf("robotics")
            ).single()
        )
    }

    private fun raw(engine: String, rank: Int, title: String, url: String) =
        AgentWebIntelligenceRawResult(engine, rank, title, url, "Evidence")

    private fun response(url: String, contentType: String, body: String) =
        AgentWebIntelligenceFetched(url, contentType, body.toByteArray(), 5L)

    private fun testDocument(url: String, content: String) = AgentWebIntelligenceDocument(
        url = url,
        title = "Evidence",
        content = content,
        contentType = "text/html",
        contentSha256 = "test",
        retrievedAtMillis = 1L,
        expiresAtMillis = 2L,
        links = emptyList(),
        metadata = emptyMap(),
        vector = floatArrayOf(1F)
    )

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

    private class ParallelResearchFetcher : AgentWebIntelligenceFetcher {
        private val active = AtomicInteger()
        private val activeByHost = ConcurrentHashMap<String, AtomicInteger>()
        val maxActive = AtomicInteger()
        val maxPerHost = AtomicInteger()

        override fun fetch(
            url: String,
            maxBytes: Long,
            timeoutMillis: Long,
            cancellationToken: AgentNativeToolCancellationToken,
            checkpoint: () -> Unit
        ): AgentWebIntelligenceFetched {
            checkpoint()
            if (url.contains("search.brave.com/search")) {
                return fetched(
                    url,
                    "text/html",
                    listOf(
                        "https://same.example.test/evidence-a",
                        "https://same.example.test/evidence-b",
                        "https://fail.example.test/evidence",
                        "https://one.example.test/evidence",
                        "https://two.example.test/evidence",
                        "https://three.example.test/evidence",
                        "https://four.example.test/evidence",
                        "https://five.example.test/evidence"
                    ).mapIndexed { index, target ->
                        "<a href=\"$target\">Parallel evidence ${index + 1}</a>"
                    }.joinToString("\n")
                )
            }
            val host = java.net.URI(url).host
            if (host == "fail.example.test") {
                throw AgentWebMediaException("source_failed", "Source failed", retryable = true)
            }
            val hostActive = activeByHost.computeIfAbsent(host) { AtomicInteger() }
            val globalNow = active.incrementAndGet()
            val hostNow = hostActive.incrementAndGet()
            maxActive.accumulateAndGet(globalNow, ::maxOf)
            maxPerHost.accumulateAndGet(hostNow, ::maxOf)
            try {
                repeat(15) {
                    if (cancellationToken.isCancellationRequested) {
                        throw AgentNativeToolCancelledException()
                    }
                    Thread.sleep(10L)
                }
                val paragraph = "Independent evidence from $host explains the architecture, observed behavior, " +
                    "verification details, limitations, and reproducible results. "
                return fetched(
                    url,
                    "text/html",
                    "<html><head><title>$host evidence</title></head><body><article>" +
                        paragraph.repeat(12) +
                        "</article></body></html>"
                )
            } finally {
                hostActive.decrementAndGet()
                active.decrementAndGet()
            }
        }

        private fun fetched(url: String, contentType: String, body: String) =
            AgentWebIntelligenceFetched(url, contentType, body.toByteArray(), 5L)
    }

    private class CountingPageFetcher(
        private val delayMillis: Long = 0L
    ) : AgentWebIntelligenceFetcher {
        val calls = AtomicInteger()
        val lastTimeoutMillis = AtomicLong()

        override fun fetch(
            url: String,
            maxBytes: Long,
            timeoutMillis: Long,
            cancellationToken: AgentNativeToolCancellationToken,
            checkpoint: () -> Unit
        ): AgentWebIntelligenceFetched {
            calls.incrementAndGet()
            lastTimeoutMillis.set(timeoutMillis)
            val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(delayMillis)
            while (System.nanoTime() < deadline) {
                checkpoint()
                if (cancellationToken.isCancellationRequested) throw AgentNativeToolCancelledException()
                Thread.sleep(10L)
            }
            val paragraph = "Cached public article evidence with enough readable content and metadata. "
            return AgentWebIntelligenceFetched(
                url = url,
                contentType = "text/html",
                body = (
                    "<html><head><title>Cached article</title></head><body><article>" +
                        paragraph.repeat(20) +
                        "</article></body></html>"
                    ).toByteArray(),
                durationMillis = delayMillis
            )
        }
    }

    private data class RecordedRequest(
        val url: String,
        val headers: Map<String, String>
    )

    private class WigoloFetcher :
        AgentWebIntelligenceFetcher,
        AgentWebIntelligenceRequestFetcher {
        val requests = mutableListOf<RecordedRequest>()

        override fun fetch(
            url: String,
            maxBytes: Long,
            timeoutMillis: Long,
            cancellationToken: AgentNativeToolCancellationToken,
            checkpoint: () -> Unit
        ): AgentWebIntelligenceFetched =
            fetch(url, maxBytes, timeoutMillis, emptyMap(), cancellationToken, checkpoint)

        @Synchronized
        override fun fetch(
            url: String,
            maxBytes: Long,
            timeoutMillis: Long,
            headers: Map<String, String>,
            cancellationToken: AgentNativeToolCancellationToken,
            checkpoint: () -> Unit
        ): AgentWebIntelligenceFetched {
            checkpoint()
            requests += RecordedRequest(url, headers)
            return when {
                url.contains("api.search.brave.com") -> fetched(
                    url,
                    "application/json",
                    """
                    {"results":[{"title":"SignalASI interface","url":"https://design.example.test/signalasi",
                    "source":"design.example.test","properties":{"url":"https://cdn.example.test/interface.jpg",
                    "width":1600,"height":900},"thumbnail":{"src":"https://cdn.example.test/interface-thumb.jpg"}}]}
                    """.trimIndent()
                )
                url.contains("duckduckgo.com/?") -> fetched(
                    url,
                    "text/html",
                    """<script>window.__search = {vqd='123-456'};</script>"""
                )
                url.contains("duckduckgo.com/i.js") -> fetched(
                    url,
                    "application/json",
                    """
                    {"results":[{"title":"SignalASI mobile agent","url":"https://images.example.test/article",
                    "image":"https://cdn.example.test/signalasi.png","thumbnail":"https://cdn.example.test/signalasi-thumb.png",
                    "width":1200,"height":800}]}
                    """.trimIndent()
                )
                url.contains("api2.marginalia-search.com") -> fetched(
                    url,
                    "application/json",
                    """
                    {"results":[{"title":"Independent SignalASI notes","url":"https://indie.example.test/signalasi",
                    "description":"A small-web SignalASI source."}]}
                    """.trimIndent()
                )
                url.contains("api.github.com/search/code") -> fetched(
                    url,
                    "application/json",
                    """
                    {"items":[{"name":"AgentLoop.kt","path":"apps/android/AgentLoop.kt",
                    "html_url":"https://github.com/signalasi/SignalASI/blob/main/apps/android/AgentLoop.kt",
                    "repository":{"full_name":"signalasi/SignalASI","description":"Mobile super agent",
                    "updated_at":"2026-07-27T00:00:00Z"}}]}
                    """.trimIndent()
                )
                else -> error("No Wigolo test route for $url")
            }
        }

        private fun fetched(url: String, contentType: String, body: String) =
            AgentWebIntelligenceFetched(url, contentType, body.toByteArray(), 5L)
    }
}
