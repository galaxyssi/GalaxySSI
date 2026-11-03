package com.galaxyssi.watch

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchWeatherEvidenceTest {
    private fun fallback(raw: String, locale: String = "values-zh"): String? {
        val document = javax.xml.parsers.DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(java.io.File("src/main/res/$locale/weather_evidence.xml"))
        val nodes = document.getElementsByTagName("string")
        val copy = (0 until nodes.length).associate {
            val node = nodes.item(it) as org.w3c.dom.Element
            node.getAttribute("name") to node.textContent
        }
        return WatchWeatherEvidence.fallback(raw, copy.getValue("weather_evidence_rain_probability"),
            copy.getValue("weather_evidence_summary_unavailable"))
    }
    private fun evidence(date: String = "2026-09-17"): String {
        val content = """{"provider":"Open-Meteo","geocoding_source":"https://geocoding-api.open-meteo.com/v1/search","location":{"name":"Zhuhai"},"timezone":"Asia/Shanghai","forecast_date":"$date","daily":{"time":["2026-09-17"],"temperature_2m_min":[25],"temperature_2m_max":[30],"precipitation_probability_max":[null]},"daily_units":{"temperature_2m_min":"°C","temperature_2m_max":"°C","precipitation_probability_max":"%"}}"""
        return JSONObject("""{"status":"completed","evidence_pack":{"items":[{"url":"https://api.open-meteo.com/v1/forecast"}]}}""")
            .apply { getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0).put("content", content) }.toString()
    }
    @Test fun fallbackPreservesRequestedDateAndUnitsWithoutInventingMissingRain() {
        val answer = requireNotNull(fallback(evidence()))
        assertTrue(answer.contains("2026-09-17"))
        assertTrue(answer.contains("25°C–30°C"))
        assertTrue(answer.contains("文字分析暂未完成"))
        assertFalse(answer.contains("降雨概率"))
    }
    @Test fun rejectsUnverifiedAndMismatchedDates() {
        assertNull(fallback(evidence("2026-09-18")))
        assertNull(fallback("{}"))
    }
    @Test fun localizedCopyPreservesRainValueAndSource() {
        for ((locale, label) in listOf("values-zh" to "降雨概率", "values" to "Rain probability")) {
            val answer = requireNotNull(fallback(evidence().replace("[null]", "[60]"), locale))
            assertTrue(answer.contains("$label 60%"))
            assertTrue(answer.contains("[Open-Meteo](https://api.open-meteo.com/v1/forecast)"))
        }
    }
    @Test fun userCancellationNeverReturnsFallbackButDeadlineMay() {
        val operation = WatchApiOperation()
        operation.expire()
        assertTrue(operation.permitsEvidenceFallback())
        operation.cancel()
        assertFalse(operation.permitsEvidenceFallback())
        operation.expire()
        assertFalse(operation.permitsEvidenceFallback())
    }
}
