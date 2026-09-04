package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudWebToolLoopProgressTest {
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
