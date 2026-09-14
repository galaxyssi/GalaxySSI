package com.galaxyssi.watch
import com.galaxyssi.chat.CloudWebGrounding
import com.galaxyssi.chat.CloudWebToolLoopProgress
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class WatchAndroidWebReuseTest {
    @Test fun modelReceivesArticleNavigationWithoutTreatingItAsEvidence() {
        val article = "https://example.com/2026/09/14/new-product/"
        val result = JSONObject(CloudWebGrounding.boundedModelJson(mapOf(
            "operation" to "fetch", "status" to "completed",
            "documents" to listOf(mapOf("links" to listOf("https://example.com/", "javascript:bad", article))),
            "evidence_pack" to mapOf("items" to emptyList<Any>())
        )))
        assertEquals(article, result.getJSONArray("discovered_links").getString(0))
        assertEquals(1, result.getJSONArray("discovered_links").length())
        assertEquals(0, result.getJSONObject("evidence_pack").getJSONArray("items").length())
    }
    @Test fun emptySearchRequiresAlternateRetrievalButDoesNotLoopAfterItFails() {
        val empty = "{\"evidence_pack\":{\"items\":[]}}"
        assertNotNull(WatchWebLookup.retrievalRepairPrompt(listOf("web_search" to empty)))
        assertNull(WatchWebLookup.retrievalRepairPrompt(listOf("web_search" to empty, "web_fetch" to empty)))
        assertNull(WatchWebLookup.retrievalRepairPrompt(listOf("web_weather" to empty)))
        val listing = "{\"discovered_links\":[\"https://example.com/article\"],\"evidence_pack\":{\"items\":[{\"url\":\"https://example.com/\",\"evidence_level\":\"retrieved_body\"}]}}"
        assertNotNull(WatchWebLookup.retrievalRepairPrompt(listOf("web_search" to empty, "web_fetch" to listing)))
    }
    @Test fun androidLoopReusesSemanticCallsAndAllowsMoreThanSixUsefulCalls() {
        val loop = CloudWebToolLoopProgress()
        repeat(8) { index ->
            val args = JSONObject().put("query", "query$index").put("read_pages", true)
            val result = JSONObject().put("evidence_pack", JSONObject().put("items", org.json.JSONArray()
                .put(JSONObject().put("url", "https://example.com/article$index").put("content_sha256", "$index"))))
                .toString()
            assertTrue(loop.record("web_search", args, result))
            assertEquals(result, loop.cached("web_search", JSONObject().put("read_pages", true).put("query", "query$index")))
            assertFalse(loop.observeEvidenceBatch(listOf(result)))
        }
        assertFalse(loop.finalizationRequested)
        assertFalse(loop.observeEvidenceBatch(emptyList()))
        assertFalse(loop.observeEvidenceBatch(emptyList()))
        assertTrue(loop.observeEvidenceBatch(emptyList()))
    }
}
