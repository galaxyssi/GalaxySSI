package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudWebToolLoopProgressTest {
    @Test fun aRetrievedPageIsReusedOnlyForEquivalentUnfocusedReads() {
        val progress = CloudWebToolLoopProgress()
        val args = JSONObject().put("url", "https://example.test/page")
        val body = JSONObject().put("status", "completed").put("evidence_pack", JSONObject()
            .put("items", JSONArray().put(JSONObject().put("url", args.getString("url"))
                .put("evidence_level", "retrieved_body").put("excerpt", "The actual page body.")))).toString()
        progress.record("web_fetch", args, body)
        assertEquals(body, progress.cached("web_extract", args))
        assertNull(progress.cached("web_extract", JSONObject(args.toString()).put("fields", JSONArray().put("date"))))
        assertNull(progress.cached("web_fetch", JSONObject(args.toString()).put("force", true)))
        assertNull(progress.cached("web_fetch", JSONObject(args.toString()).put("focus", "missing counterexample")))
        assertNull(CloudWebToolLoopProgress().cached("web_extract", args))
    }

    @Test fun snippetsAndDifferentUrlsCannotSatisfyARequestedPageRead() {
        val progress = CloudWebToolLoopProgress()
        val args = JSONObject().put("url", "https://example.test/page")
        val snippet = """{"status":"completed","evidence_pack":{"items":[{"url":"https://example.test/page","evidence_level":"discovery_snippet"}]}}"""
        progress.record("web_fetch", args, snippet)
        assertNull(progress.cached("web_extract", args))
        assertNull(progress.cached("web_extract", JSONObject().put("url", "https://another.example.test/page")))
    }

    @Test fun timedOutPageIsNotFetchedAgainThroughAnotherReadTool() {
        val progress = CloudWebToolLoopProgress()
        val arguments = JSONObject().put("url", "https://example.test/page?q=%E4%B8%AD")
        val failure = """{"status":"failed","error_code":"web_source_timeout","retryable":false}"""
        progress.record("web_fetch", arguments, failure)
        assertEquals(failure, progress.cached("web_extract", arguments))
        assertNull(progress.cached("web_extract", JSONObject().put("url", "https://another.example.test/page")))
        assertNull(CloudWebToolLoopProgress().cached("web_fetch", arguments))
    }

    @Test
    fun distinctModelCallsAreNotStoppedByAnAppCountBudget() {
        val progress = CloudWebToolLoopProgress()

        repeat(1_000) { index ->
            val arguments = JSONObject().put("query", "evidence-$index")
            assertTrue(progress.record("web_search", arguments, "result-$index"))
        }

        assertEquals(
            "result-999",
            progress.cached("web_search", JSONObject().put("query", "evidence-999"))
        )
        assertFalse(progress.finalizationRequested)
    }

    @Test
    fun equivalentJsonArgumentsReuseTheSameToolResult() {
        val progress = CloudWebToolLoopProgress()
        val first = JSONObject()
            .put("query", "GalaxySSI")
            .put("filters", JSONObject().put("year", 2026).put("kind", "news"))
            .put("engines", JSONArray().put("brave").put("bing"))
        val reordered = JSONObject()
            .put("engines", JSONArray().put("brave").put("bing"))
            .put("filters", JSONObject().put("kind", "news").put("year", 2026))
            .put("query", "GalaxySSI")

        assertNull(progress.cached("web_search", first))
        assertTrue(progress.record("web_search", first, "evidence"))
        assertEquals("evidence", progress.cached("WEB_SEARCH", reordered))
        assertFalse(progress.record("web_search", reordered, "duplicate"))
    }

    @Test
    fun noProgressFinalizationAndRepairSignalsAreOneShot() {
        val progress = CloudWebToolLoopProgress()

        assertTrue(progress.requestRepair("citations"))
        assertFalse(progress.requestRepair("citations"))
        assertTrue(progress.requestRepair("protocol"))
        assertTrue(progress.requestFinalization())
        assertTrue(progress.finalizationRequested)
        assertFalse(progress.requestFinalization())
    }
}
