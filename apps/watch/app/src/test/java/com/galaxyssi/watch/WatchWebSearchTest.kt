package com.galaxyssi.watch

import com.galaxyssi.chat.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import okhttp3.OkHttpClient
import okhttp3.Request

class WatchWebSearchTest {
    @Test fun repeatedLookupsRefreshInsteadOfReplayingPreviousFailures() {
        val task = WatchTask.create("api", "profile", "model", "Today's technology news")
        val previous = task.copy(id = "previous", state = TaskState.COMPLETED, reply = "No articles found")
        val context = previous.copy(id = "context", prompt = "My interests", reply = "Space and chips")
        val leaked = previous.copy(id = "leaked", prompt = "Search again", reply = "Trying again. {\"tool_calls\":[]}")
        assertEquals(listOf(context), WatchWebLookup.freshLookupHistory(task, listOf(previous, context, leaked)))
    }
    @Test fun nestedToolDecisionsAreExecutedInsteadOfDisplayed() {
        val tool = """{"tool_calls":[{"name":"web_search","arguments":{"query":"technology news","read_pages":true}}]}"""
        for (answer in listOf(tool, JSONObject(tool), "```json\n$tool\n```")) {
            val parsed = WatchWebLookup.parseDecision(JSONObject().put("answer", answer).toString())
            assertFalse(parsed.has("answer"))
            assertEquals("web_search", parsed.getJSONArray("tool_calls").getJSONObject(0).getString("name"))
        }
        assertEquals("web_search", WatchWebLookup.parseDecision("The previous search returned no results. Trying again.\n\n$tool")
            .getJSONArray("tool_calls").getJSONObject(0).getString("name"))
        assertThrows(ApiFailure::class.java) { WatchWebLookup.parseDecision("Trying again. $tool\n$tool") }
        val jsonCode = "```json\n{\"temperature\":29}\n```"
        assertEquals(jsonCode, WatchWebLookup.parseDecision(JSONObject().put("answer", jsonCode).toString()).getString("answer"))
        assertThrows(ApiFailure::class.java) { WatchWebLookup.parseDecision("""{"answer":{"evidence_pack":[]}}""") }
        assertThrows(ApiFailure::class.java) { WatchWebLookup.parseDecision("""[{"tool":"web_search"}]""") }
    }
    @Test fun androidRichBlocksPreserveNewsAndNarrowTables() {
        val raw = "# News\n\n- First\n- Second\n\n| Name | Date |\n| --- | --- |\n| Launch | Today |\n\n```kotlin\nval count = 1\n```"
        val blocks = WatchRichReply.blocks(raw)
        assertTrue(blocks.any { it.type == AgentRichBlockType.HEADING && it.text == "News" })
        assertTrue(blocks.any { it.type == AgentRichBlockType.CODE && it.text.contains("val count") })
        assertEquals("\u2022 First\n\u2022 Second", WatchRichReply.text(blocks.first { it.type == AgentRichBlockType.LIST }))
        assertEquals("\u2611 Done\n\u2610 Pending\n1. Next", WatchRichReply.text(WatchRichReply.blocks("- [x] Done\n- [ ] Pending\n1. Next").single()))
        assertEquals("Name: Launch\nDate: Today", WatchRichReply.text(blocks.first { it.type == AgentRichBlockType.TABLE }))
        val rich = """{"version":1,"blocks":[{"type":"heading","text":"News"},{"type":"link","title":"Source","uri":"https://example.com"}]}"""
        assertEquals(2, WatchRichReply.blocks(WatchWebLookup.parseDecision(JSONObject().put("answer", JSONObject(rich)).toString()).getString("answer")).size)
    }
    @Test fun allAndroidToolsAndSourceFamiliesAreIncluded() {
        val tools = CloudWebGrounding.openAiTools()
        val names = (0 until tools.length()).map { tools.getJSONObject(it).getJSONObject("function").getString("name") }.toSet()
        assertTrue(names.containsAll(setOf("web_search", "web_weather", "web_image_search", "web_fetch", "web_crawl",
            "web_extract", "web_cache", "web_find_similar", "web_research", "web_agent", "web_diff", "web_watch")))
        val engines = AgentWebIntelligenceEngineCatalog.entries
        println("ANDROID_WEB_SOURCES=${engines.size}")
        assertTrue(engines.size > 100)
        assertTrue(engines.any { it.id == "arxiv" })
        assertTrue(engines.any { it.id == "china_weather" })
        assertTrue(engines.any { it.id == "reuters_news" })
    }
    @Test fun stopCancelsModelAndAndroidWebTransportTogether() {
        val operation = WatchApiOperation()
        val call = OkHttpClient().newCall(Request.Builder().url("https://example.com/").build())
        operation.attach(call)
        var webStopped = false
        operation.webToken.invokeOnCancellation { webStopped = true }
        operation.cancel()
        assertTrue(call.isCanceled()); assertTrue(webStopped)
        assertThrows(java.io.IOException::class.java) { operation.attach(OkHttpClient().newCall(call.request())) }
    }
    @Test fun androidPublicAddressPolicyBlocksLocalSources() {
        assertFalse(AgentPublicAddressPolicy.isPublic(java.net.InetAddress.getByName("127.0.0.1")))
        assertFalse(AgentPublicAddressPolicy.isPublic(java.net.InetAddress.getByName("192.168.0.1")))
        assertTrue(AgentPublicAddressPolicy.isPublic(java.net.InetAddress.getByName("8.8.8.8")))
    }
    @Test fun decisionRejectsMixedAnswerAndToolInstructions() {
        assertEquals("Hello", WatchWebLookup.parseDecision("{\"answer\":\"Hello\"}").getString("answer"))
        assertThrows(ApiFailure::class.java) { WatchWebLookup.parseDecision("{\"answer\":\"Hello\",\"tool_calls\":[{\"name\":\"web_search\"}]}") }
        assertEquals("Plain answer", WatchWebLookup.parseDecision("Plain answer").getString("answer"))
        assertEquals("[Source](https://example.com)", WatchWebLookup.parseDecision("[Source](https://example.com)").getString("answer"))
    }
    private val location get() = JSONObject().put("location", "Zhuhai").put("region", "Guangdong").put("country_code", "CN")
    private val geo = """{"results":[{"name":"Zhuhai","admin1":"Guangdong","country_code":"CN","latitude":22.27,"longitude":113.58}]}"""
    private fun forecast(date: String) = """{"timezone":"Asia/Shanghai","current":{"time":"2026-09-14T15:00","temperature_2m":29.5},"current_units":{"temperature_2m":"C"},"daily":{"time":["$date"],"temperature_2m_max":[31.0],"temperature_2m_min":[25.0]},"daily_units":{}}"""
    @Test fun sharedWeatherVerifiesCityAndLocalForecastDate() {
        val now = java.time.Instant.parse("2026-09-14T07:00:00Z").toEpochMilli()
        val result = CloudWeatherLookup.execute(location, { if ("geocoding" in it) geo else forecast("2026-09-14") }, now)
        val json = JSONObject(result)
        assertEquals("completed", json.getString("status"))
        assertTrue(json.toString().contains("29.5"))
        assertTrue(json.toString().contains("weather_model_estimate_not_station_observation"))
        assertThrows(IllegalArgumentException::class.java) {
            CloudWeatherLookup.execute(location, { if ("geocoding" in it) geo else forecast("2026-09-13") }, now)
        }
    }
    @Test fun ambiguousOrWrongRegionDoesNotFetchAnotherCityWeather() {
        var count = 0
        val result = CloudWeatherLookup.execute(location.put("region", "Jiangsu"), { count++; geo })
        assertEquals("needs_location_clarification", result["status"])
        assertEquals(1, count)
    }
}
