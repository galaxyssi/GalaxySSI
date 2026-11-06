package com.galaxyssi.chat

import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthTrendAnalysisTest {
    private val day = LocalDate.of(2026, 11, 1)
    private val spec = HealthTrendSpec(HealthMetric.WEIGHT, day, day.plusDays(3), ZoneId.of("UTC"), "kg",
        HealthTrendAggregation.MINIMUM, HealthTrendSource(manualOnly = true))

    private fun point(value: String, dayIndex: Long, minutes: Long = 0, unit: String = "kg") =
        HealthObservationPolicy.observation(HealthDraft(spec.metric, mapOf("weight" to value), unit,
            spec.from + dayIndex * 86_400_000L + minutes * 60_000L, note = "PRIVATE_NOTE"))

    @Test fun disclosureContainsOnlyFilteredEndpointFactsAndCoverage() {
        val first = point("70", 0)
        val last = point("67.5", 3)
        val trend = HealthTrendBuilder(spec).apply {
            listOf(point("65", -1), point("73", 0, 1), first, point("160", 1, unit = "lb"), last).forEach(::add)
        }.finish()
        val preview = HealthTrendAnalysis.project(trend, "PRIVATE_POLICY")
        val fact = preview.facts.single()
        assertEquals(first.id, fact.first.recordId)
        assertEquals(last.id, fact.last.recordId)
        val payload = HealthAnalysis.payload(preview)
        assertEquals("filtered_trend", payload.getString("scope"))
        assertEquals("MINIMUM", payload.getString("aggregation"))
        assertEquals(3, payload.getInt("numeric_records"))
        assertEquals(2, payload.getInt("missing_days"))
        assertEquals(1, payload.getInt("excluded_other_units"))
        val row = payload.getJSONArray("facts").getJSONObject(0)
        assertEquals("70", row.getJSONObject("first").getString("value"))
        assertEquals(2, row.getJSONObject("first").getInt("record_count"))
        assertEquals(4, row.getJSONObject("last").getInt("index"))
        assertEquals("-2.5", row.getString("delta"))
        listOf(first.id, last.id, day.toString(), "PRIVATE_NOTE", "PRIVATE_POLICY", "160").forEach {
            assertFalse(it, payload.toString().contains(it))
        }
    }

    @Test fun onePointNeverReportsAZeroChangeAndNoDataHasNoFacts() {
        val empty = HealthTrendAnalysis.project(HealthTrendBuilder(spec).finish(), "p")
        assertFalse(empty.hasData)
        val one = HealthTrendAnalysis.project(HealthTrendBuilder(spec).apply { add(point("70", 0)) }.finish(), "p")
        assertTrue(one.hasData)
        assertNull(one.facts.single().delta)
        val row = one.payload().getJSONArray("facts").getJSONObject(0)
        assertFalse(row.has("delta"))
        assertFalse(row.has("last"))
    }

    @Test fun modelCannotBroadenTheTrendIntoAWeeklyReportOrOtherFacts() {
        val trend = HealthTrendBuilder(spec).apply { add(point("70", 0)) }.finish()
        val preview = HealthTrendAnalysis.project(trend, "p")
        assertEquals(listOf("f1"), HealthAnalysis.decodeReply(
            """{"fact_ids":["f1"],"actions":["ADD_RECORD"]}""", preview).factKeys)
        assertThrows(HealthAnalysisInvalidReply::class.java) {
            HealthAnalysis.decodeReply("""{"fact_ids":["f1"],"actions":["WEEKLY_REPORT"]}""", preview)
        }
        assertThrows(HealthAnalysisInvalidReply::class.java) {
            HealthAnalysisFollowUp.decode("""{"status":"ANSWERED","sections":[{"topic":"CHANGES","fact_ids":["f2"]}],"actions":[]}""", preview)
        }
        assertThrows(HealthAnalysisInvalidReply::class.java) {
            HealthAnalysisFollowUp.decode("""{"status":"ANSWERED","sections":[],"actions":["WEEKLY_REPORT"]}""", preview)
        }
    }
}
