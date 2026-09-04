package com.galaxyssi.chat

import java.net.URI
import java.net.URLDecoder
import java.util.Collections
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentWebResearchPlanTest {
    @Test
    fun modelQueryPlanIsPreservedWithoutHostKeywordExpansion() {
        val plan = AgentWebResearchPlanCodec.decode(
            primaryQuery = "Compare the evidence",
            rawPlan = listOf(
                mapOf(
                    "query" to "GalaxySSI primary documentation",
                    "purpose" to "Primary implementation evidence",
                    "verticals" to listOf("docs", "code"),
                    "categories" to listOf("智能体 工程"),
                    "engines" to listOf("github", "mdn")
                ),
                mapOf(
                    "query" to "GalaxySSI independent field report",
                    "purpose" to "Independent verification"
                )
            )
        )

        assertEquals(
            listOf(
                "GalaxySSI primary documentation",
                "GalaxySSI independent field report"
            ),
            plan.map(AgentWebResearchQueryPlanItem::query)
        )
        assertEquals(setOf("docs", "code"), plan.first().verticals.map { it.wireValue }.toSet())
        assertEquals(setOf("智能体 工程"), plan.first().categories)
        assertEquals(listOf("github", "mdn"), plan.first().engines)
        assertFalse(plan.any { "latest evidence" in it.query || "official documentation" in it.query })
    }

    @Test
    fun missingPlanUsesOnlyTheOriginalQuestion() {
        val plan = AgentWebResearchPlanCodec.decode("今天珠海天气", null)

        assertEquals(listOf("今天珠海天气"), plan.map(AgentWebResearchQueryPlanItem::query))
    }

    @Test
    fun unscopedSearchDoesNotClassifyTopicsFromQueryKeywords() {
        val coordinator = AgentWebIntelligenceSearchCoordinator(PlanFetcher())

        val weatherWords = coordinator.selectEngines(
            "latest weather forecast today",
            12,
            emptyList(),
            emptySet()
        )
        val unrelatedWords = coordinator.selectEngines(
            "historical painting technique",
            12,
            emptyList(),
            emptySet()
        )
        val modelSelectedWeather = coordinator.selectEngines(
            "historical painting technique",
            12,
            emptyList(),
            setOf(AgentWebIntelligenceVertical.WEATHER)
        )

        assertEquals(unrelatedWords, weatherWords)
        assertTrue(modelSelectedWeather.any { engine ->
            AgentWebIntelligenceEngineCatalog.entries.first { it.id == engine }.vertical ==
                AgentWebIntelligenceVertical.WEATHER
        })
    }

    @Test
    fun researchExecutesTheModelPlanAndReturnsPerQueryCoverage() {
        val fetcher = PlanFetcher()
        val service = AgentWebIntelligenceService(
            fetcher = fetcher,
            store = AgentInMemoryWebIntelligenceStore()
        )

        val output = service.invoke(
            "agent",
            mapOf(
                "query" to "Compare GalaxySSI evidence",
                "query_plan" to listOf(
                    mapOf(
                        "query" to "GalaxySSI primary source",
                        "purpose" to "Find the primary source",
                        "engines" to listOf("brave")
                    ),
                    mapOf(
                        "query" to "GalaxySSI independent review",
                        "purpose" to "Cross-check independently",
                        "engines" to listOf("brave")
                    )
                ),
                "evidence_limit" to 4,
                "engine_fanout" to 1,
                "profile" to "fast",
                "use_cache" to false,
                "timeout_ms" to 5_000,
                "page_read_parallelism" to 4,
                "per_host_parallelism" to 1,
                "page_read_timeout_ms" to 5_000,
                "early_complete" to false
            )
        )

        val research = output["research"] as Map<*, *>
        val coverage = (research["coverage"] as List<*>).filterIsInstance<Map<*, *>>()
        val metadata = output["metadata"] as Map<*, *>
        val evidencePack = output["evidence_pack"] as Map<*, *>
        val researchContext = evidencePack["research_context"] as Map<*, *>

        assertEquals("model_supplied", metadata["query_plan_source"])
        assertEquals(2, metadata["queries_executed"])
        assertEquals(listOf("covered", "covered"), coverage.map { it["status"] })
        assertTrue(coverage.all { (it["retrieved_document_count"] as Number).toInt() >= 1 })
        assertEquals(emptyList<String>(), research["unresolved_queries"])
        assertEquals(2, (researchContext["query_plan"] as List<*>).size)
        assertEquals(2, (researchContext["coverage"] as List<*>).size)
        assertEquals(
            setOf("GalaxySSI primary source", "GalaxySSI independent review"),
            fetcher.searchQueries.toSet()
        )
        assertFalse(fetcher.searchQueries.any {
            "latest evidence" in it || "official documentation" in it || "limitations risks" in it
        })
    }

    @Test
    fun roundRobinMergeDoesNotLetTheFirstSubqueryConsumeEveryCandidate() {
        val merged = roundRobinWebResearchResults(
            listOf(
                listOf(result("https://a.test/1"), result("https://a.test/2")),
                listOf(result("https://b.test/1"), result("https://b.test/2"))
            )
        )

        assertEquals(
            listOf(
                "https://a.test/1",
                "https://b.test/1",
                "https://a.test/2",
                "https://b.test/2"
            ),
            merged.keys.toList()
        )
    }

    @Test
    fun learnedSourceCategoriesAcceptTheModelsNaturalLanguageLabels() {
        val store = AgentInMemoryWebIntelligenceStore { 900_000L }
        val result = AgentWebIntelligenceResult(
            title = "Independent robotics field report",
            url = "https://robot-field-report.example/current",
            excerpt = "Current public robotics evidence",
            publishedAt = "",
            vertical = AgentWebIntelligenceVertical.TECHNOLOGY
        )
        repeat(3) { index ->
            store.observeSourceCandidates(
                query = "robotics evidence $index",
                categoryTags = setOf("机器人 运动规划", "具身智能"),
                results = listOf(result)
            )
        }

        assertEquals(
            setOf("机器人 运动规划", "具身智能", "technology"),
            store.learnedSources().single().categoryTags
        )
    }

    private fun result(url: String): AgentNativeJsonObject = linkedMapOf("url" to url)

    private class PlanFetcher : AgentWebIntelligenceFetcher {
        val searchQueries = Collections.synchronizedList(mutableListOf<String>())

        override fun fetch(
            url: String,
            maxBytes: Long,
            timeoutMillis: Long,
            cancellationToken: AgentNativeToolCancellationToken,
            checkpoint: () -> Unit
        ): AgentWebIntelligenceFetched {
            checkpoint()
            val uri = URI(url)
            if (uri.host == "search.brave.com") {
                val query = uri.rawQuery.orEmpty().split('&')
                    .mapNotNull { part ->
                        val key = part.substringBefore('=')
                        if (key == "q") URLDecoder.decode(part.substringAfter('=', ""), "UTF-8") else null
                    }
                    .firstOrNull()
                    .orEmpty()
                searchQueries += query
                val suffix = if ("primary" in query) "primary" else "independent"
                val body = (1..2).joinToString("\n") { index ->
                    "<a href=\"https://$suffix-$index.example.test/report\">$suffix report $index</a>"
                }
                return AgentWebIntelligenceFetched(url, "text/html", body.toByteArray(), 5L)
            }
            val paragraph = "Retrieved public evidence from ${uri.host} with independently verifiable details, " +
                "dates, context, limitations, and source attribution. "
            val body = "<html><head><title>${uri.host}</title></head><body><article>" +
                paragraph.repeat(16) + "</article></body></html>"
            return AgentWebIntelligenceFetched(url, "text/html", body.toByteArray(), 5L)
        }
    }
}
