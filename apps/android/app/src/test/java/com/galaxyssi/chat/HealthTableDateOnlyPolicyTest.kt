package com.galaxyssi.chat

import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class HealthTableDateOnlyPolicyTest {
    private val headers = listOf("date", "systolic", "diastolic", "unit")
    private val now = Instant.parse("2025-01-01T00:00:00Z").toEpochMilli()
    private val mapping = HealthTablePolicy.suggest(headers, HealthMetric.BLOOD_PRESSURE).copy(zone = "Asia/Shanghai")

    @Test fun csvAndJsonApplyTheChosenTimeOnlyToValidDatesInTheSelectedFormat() {
        val dates = listOf(
            HealthTableDate.ISO to "2024-02-29",
            HealthTableDate.YMD to "2024-02-29",
            HealthTableDate.YMD_SECONDS to "2024-02-29",
            HealthTableDate.SLASH_YMD to "2024/02/29",
            HealthTableDate.DMY to "29/02/2024",
            HealthTableDate.MDY to "02/29/2024",
        )
        for (format in listOf("csv", "json")) for ((date, raw) in dates) {
            val m = mapping.copy(date = date)
            val unconfirmed = evaluate(format, raw, m)
            assertEquals(HealthTableRowState.MISSING, unconfirmed.state)
            assertEquals("date_only_time", unconfirmed.issue)
            assertNull(unconfirmed.draft)
            val confirmed = evaluate(format, raw, m.copy(dateOnlyTime = "08:15"))
            assertTrue(confirmed.usedDateOnlyTime)
            val saved = requireNotNull(confirmed.draft)
            assertEquals(Instant.parse("2024-02-29T00:15:00Z").toEpochMilli(), saved.measuredAt)
            assertTrue(saved.evidence!!.rawText.contains("date: $raw"))
            assertTrue(saved.evidence!!.rawText.contains("Confirmed date-only time: 08:15"))
        }
    }

    @Test fun anExplicitDateOffsetAndExistingTimestampsAreNotOverwritten() {
        val m = mapping.copy(dateOnlyTime = "08:15", zone = "America/New_York")
        val offsetDate = evaluate("json", "2024-02-29+08:00", m)
        assertTrue(offsetDate.usedDateOnlyTime)
        assertEquals(Instant.parse("2024-02-29T00:15:00Z").toEpochMilli(), offsetDate.draft!!.measuredAt)
        val full = evaluate("csv", "2024-02-29T03:30:00Z", m)
        assertFalse(full.usedDateOnlyTime)
        assertEquals(Instant.parse("2024-02-29T03:30:00Z").toEpochMilli(), full.draft!!.measuredAt)
        assertFalse(full.draft!!.evidence!!.rawText.contains("Confirmed date-only time"))
        val local = evaluate("csv", "2024-02-29 03:30", m.copy(date = HealthTableDate.YMD))
        assertEquals(Instant.parse("2024-02-29T08:30:00Z").toEpochMilli(), local.draft!!.measuredAt)
    }

    @Test fun invalidDatesAmbiguousZonesAndUnknownTimesAreNotInvented() {
        fun bad(raw: String, m: HealthTableMapping) {
            val evaluation = evaluate("csv", raw, m)
            assertEquals(raw, HealthTableRowState.INVALID, evaluation.state)
            assertEquals(raw, "time", evaluation.issue)
            assertNull(evaluation.draft)
        }
        val explicit = mapping.copy(dateOnlyTime = "08:15")
        bad("2024-02-30", explicit)
        bad("29/02/2024", explicit.copy(date = HealthTableDate.MDY))
        bad("2024-02-29", explicit.copy(dateOnlyTime = "24:00"))
        bad("45351", explicit)
        bad("45351", explicit.copy(date = HealthTableDate.EXCEL))
        val dst = explicit.copy(zone = "America/New_York")
        bad("2024-11-03", dst.copy(dateOnlyTime = "01:30"))
        bad("2024-03-10", dst.copy(dateOnlyTime = "02:30"))
        val midnight = evaluate("json", "2024-02-29", explicit.copy(dateOnlyTime = "00:00"))
        assertEquals(Instant.parse("2024-02-28T16:00:00Z").toEpochMilli(), midnight.draft!!.measuredAt)
    }

    private fun evaluate(format: String, date: String, m: HealthTableMapping) = HealthTablePolicy.evaluate(
        HealthTableBatch("3d12b26a-3c52-431e-99dc-c54c74e60071", "46e37cba-e37d-4dce-ac7f-2c3accdb547c",
            "a".repeat(64), "sample.$format", format, headers = headers, mapping = m),
        HealthTableRow(1, mapOf("date" to date, "systolic" to "124", "diastolic" to "82", "unit" to "mmHg")), now,
    )
}
