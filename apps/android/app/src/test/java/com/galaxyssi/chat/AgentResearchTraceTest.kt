package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentResearchTraceTest {
    @Test fun deduplicatesQueriesAndSourcesWithoutDroppingQueryParameters() {
        val trace = AgentResearchTrace().merge(AgentResearchTrace(
            listOf("  AI   news ", "ai news", "chip research"), listOf(
                AgentResearchTrace.Source("https://example.org/a?id=1#part", ""),
                AgentResearchTrace.Source("https://example.org/a?id=1", "Title"),
                AgentResearchTrace.Source("https://example.org/a?id=2", "Other"))))
        assertEquals(listOf("AI news", "chip research"), trace.queries)
        assertEquals(2, trace.sources.size)
        assertEquals("Title", trace.sources.first().title)
        assertEquals(trace, trace.merge(trace))
    }

    @Test fun rejectsNonWebAndCredentialUrls() {
        for (url in listOf("javascript:alert(1)", "file:///private", "https://secret@example.org", "https://", "not a url")) {
            assertNull(AgentResearchTrace.safeUrl(url))
        }
    }

    @Test fun noSearchMeansNoDisclosure() {
        assertFalse(AgentResearchTrace.observe("terminal", JSONObject(), "https://example.org").visible)
        assertFalse(AgentResearchTrace.decode(null).visible)
    }

    @Test fun recordsRealOutputNotNumbersOrInstructionsInProse() {
        val output = """{"evidence_pack":{"items":[{"url":"https://example.org/a","title":"Source"}]},"results":[{"url":"https://example.org/a","title":"Source"}],"detail":"searched 80 sources"}"""
        val trace = AgentResearchTrace.observe("web_search", JSONObject().put("query", "real query"), output)
        assertEquals(listOf("real query"), trace.queries)
        assertEquals(1, trace.sources.size)
    }

    @Test fun plannedButUnexecutedQueriesAreNotCounted() {
        val output = """{"research":{"query_plan":[{"query":"not run"}],"executed_queries":["executed"]}}"""
        assertEquals(listOf("executed"), AgentResearchTrace.observe("web_research", JSONObject(), output).queries)
    }

    @Test fun jsonRoundTripRetainsUnknownRemoteSources() {
        val trace = AgentResearchTrace(listOf("query"), remote = true)
        assertEquals(trace, AgentResearchTrace.decode(trace.toJson()))
        assertTrue(trace.sources.isEmpty())
    }

    @Test fun boundedProjectionDeclaresPartialInsteadOfInventingTotal() {
        val trace = AgentResearchTrace().merge(AgentResearchTrace((1..514).map { "query $it" }))
        assertEquals(512, trace.queries.size)
        assertTrue(trace.truncated)
    }

    @Test fun sourceRetrievalIsNotClaimVerificationAndCannotRegress() {
        val args = JSONObject().put("query", "test")
        val found = AgentResearchTrace.observe("web_search", args,
            """{"results":[{"url":"https://example.org/a","title":"A"}]}""")
        assertEquals("discovered", found.sources.single().status)
        val body = AgentResearchTrace.observe("web_fetch", args,
            """{"evidence_pack":{"items":[{"url":"https://example.org/a","evidence_level":"retrieved_body","excerpt":"Original text"}]}}""")
        val merged = found.merge(body).merge(found)
        assertEquals("body_retrieved", merged.sources.single().status)
        assertEquals(merged, AgentResearchTrace.decode(merged.toJson()))
        assertEquals("discovered", AgentResearchTrace(sources = listOf(AgentResearchTrace.Source("https://example.org", "", "verified")))
            .merge(AgentResearchTrace()).sources.single().status)
    }

    @Test fun actualCitationsExcludeImagesAndSubstringMatches() {
        assertEquals(setOf("https://example.org/a"), AgentResearchTrace.citedUrls(
            "[A](https://example.org/a#section) ![image](https://example.org/b) https://example.org/c"))
    }
}
