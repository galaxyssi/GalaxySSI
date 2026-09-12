package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class CloudWeatherLookupTest {
    private val now = Instant.parse("2026-09-12T06:00:00Z").toEpochMilli()
    private fun args() = JSONObject().put("location", "Zhuhai").put("region", "Guangdong").put("country_code", "CN")
    private val geocoding = """{"results":[{"name":"Zhuhai","admin1":"Shandong","country_code":"CN","latitude":35.87,"longitude":120},
        {"name":"Zhuhai","admin1":"Guangdong","country_code":"CN","latitude":22.27,"longitude":113.56}]}"""
    private val forecast = """{"timezone":"Asia/Shanghai","current":{"time":"2026-09-12T14:00","temperature_2m":null},
        "current_units":{"temperature_2m":"C"},"daily":{"time":["2026-09-12"],"temperature_2m_max":[31]},"daily_units":{"temperature_2m_max":"C"}}"""

    @Test fun verifiesRegionAndLocalDateAndPreservesNullsAndAttribution() {
        val urls = mutableListOf<String>()
        val output = CloudWeatherLookup.execute(args(), { url ->
            urls += url
            if (url.contains("geocoding-api")) geocoding else forecast
        }, now)
        assertEquals(2, urls.size)
        assertTrue(urls.last().contains("latitude=22.27"))
        val encoded = AgentNativeJsonCodec.stringify(output)
        val item = JSONObject(encoded).getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
        assertTrue(item.getString("excerpt").contains("weather_model_estimate_not_station_observation"))
        assertTrue(item.getString("excerpt").contains("\"temperature_2m\":null"))
        assertEquals(now, item.getLong("retrieved_at_millis"))
        assertTrue(CloudWebGrounding.citationValidation("[source](<${urls.last()}>)", listOf("web_weather" to encoded)).valid)
    }

    @Test fun aDifferentRegionDoesNotSilentlyReturnTheWrongCity() {
        var fetches = 0
        val output = CloudWeatherLookup.execute(args().put("region", "Unknown"), { fetches++; geocoding }, now)
        assertEquals("needs_location_clarification", output["status"])
        assertEquals(1, fetches)
    }

    @Test fun staleDateIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            CloudWeatherLookup.execute(args(), { if (it.contains("geocoding-api")) geocoding
                else forecast.replace("2026-09-12", "2026-09-11") }, now)
        }
    }

    @Test fun arbitraryEndpointOrMissingRegionCannotBeRequested() {
        assertThrows(IllegalArgumentException::class.java) {
            CloudWeatherLookup.execute(JSONObject().put("url", "http://localhost"), { error("Must not fetch") }, now)
        }
    }

    @Test fun cacheEvidenceUsesTheSameBoundedVerifiedPackWithoutClaimingFreshness() {
        val output = AgentWebEvidencePack.attach(mapOf("operation" to "cache", "status" to "completed",
            "documents" to listOf(mapOf("url" to "https://example.com/report", "title" to "Stored report",
                "content" to "Stored source text. ".repeat(1000), "retrieved_at_millis" to 1L))), now)
        val compact = JSONObject(CloudWebGrounding.boundedModelJson(output))
        assertFalse(compact.has("documents"))
        assertTrue(compact.getJSONObject("evidence_pack").getString("freshness").contains("not a new fetch"))
        assertEquals(1L, compact.getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0).getLong("retrieved_at_millis"))
    }
}
