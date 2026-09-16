package com.galaxyssi.watch

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchWeatherEvidenceTest {
    private fun evidence(date: String = "2026-09-17"): String {
        val content = """{"provider":"Open-Meteo","geocoding_source":"https://geocoding-api.open-meteo.com/v1/search","location":{"name":"Zhuhai"},"timezone":"Asia/Shanghai","forecast_date":"$date","daily":{"time":["2026-09-17"],"temperature_2m_min":[25],"temperature_2m_max":[30],"precipitation_probability_max":[null]},"daily_units":{"temperature_2m_min":"°C","temperature_2m_max":"°C","precipitation_probability_max":"%"}}"""
        return JSONObject("""{"status":"completed","evidence_pack":{"items":[{"url":"https://api.open-meteo.com/v1/forecast"}]}}""")
            .apply { getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0).put("content", content) }.toString()
    }
    @Test fun fallbackPreservesRequestedDateAndUnitsWithoutInventingMissingRain() {
        val answer = requireNotNull(WatchWeatherEvidence.fallback(evidence(), true))
        assertTrue(answer.contains("2026-09-17"))
        assertTrue(answer.contains("25°C–30°C"))
        assertTrue(answer.contains("文字分析暂未完成"))
        assertFalse(answer.contains("降雨概率"))
    }
    @Test fun rejectsUnverifiedAndMismatchedDates() {
        assertNull(WatchWeatherEvidence.fallback(evidence("2026-09-18"), true))
        assertNull(WatchWeatherEvidence.fallback("{}", true))
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
