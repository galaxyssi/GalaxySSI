package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class HealthOcrSourceContextTest {
    private val local = ZoneId.of("Asia/Shanghai")
    private fun inspect(vararg lines: String, zone: ZoneId = local) =
        HealthOcrSourceContext.inspect(HealthOcrPage(1, 100, 100, lines.map { HealthOcrLine(it) }), zone)

    @Test fun recognizedNameAndExplicitSamplingTimeStaySeparateFromResultAndReportDate() {
        val value = inspect("姓名：测试用户", "采样时间：2026年11月3日 08:15:20", "报告时间：2026-11-03 12:10",
            "Glucose: 5.6 mmol/L")
        assertEquals(listOf("测试用户"), value.owners)
        assertEquals(listOf("2026年11月3日 08:15:20"), value.times)
        assertEquals(HealthOcrSampleTime(Instant.parse("2026-11-03T00:15:20Z").toEpochMilli(), local.id), value.sample)
    }

    @Test fun explicitOffsetsAreNotReinterpretedInThePhoneZone() {
        val offset = inspect("Specimen collected at: 2026-11-03T08:15:00-05:00").sample
        assertEquals(HealthOcrSampleTime(Instant.parse("2026-11-03T13:15:00Z").toEpochMilli(), "UTC-05:00"), offset)
        val utc = inspect("Measured at: 2026-11-03T08:15Z").sample
        assertEquals(HealthOcrSampleTime(Instant.parse("2026-11-03T08:15:00Z").toEpochMilli(), "UTC"), utc)
    }

    @Test fun ambiguousAndIncompleteSourceTimesRemainRawWithoutASuggestion() {
        listOf("2026-11-03", "2026-02-30 08:15", "2026-11-03 24:15", "2026-11-03 08:15 CST",
            "03/11/2026 08:15", "2026-11-03 08:15 to 09:00").forEach { text ->
            val value = inspect("Collection time: $text")
            assertEquals(text, value.times.single())
            assertNull(text, value.sample)
        }
        val value = inspect("Collection time: 2026-11-03 08:15", "Measured at: 2026-11-03 09:15")
        assertEquals(2, value.times.size)
        assertNull(value.sample)
    }

    @Test fun daylightSavingGapAndOverlapAreNotSilentlyResolved() {
        val zone = ZoneId.of("America/New_York")
        assertNull(inspect("Collection time: 2026-03-08 02:30", zone = zone).sample)
        assertNull(inspect("Collection time: 2026-11-01 01:30", zone = zone).sample)
        assertNotNull(inspect("Collection time: 2026-11-01 01:30-04:00", zone = zone).sample)
    }

    @Test fun severalOwnersDoNotShareAnAutomaticallyProposedTime() {
        val value = inspect("Patient name: Synthetic A", "Patient name: Synthetic B", "Collected at: 2026-11-03 08:15")
        assertEquals(listOf("Synthetic A", "Synthetic B"), value.owners)
        assertNull(value.sample)
    }

    @Test fun unlabeledDetailsAreNotMatchedAndRepeatedExactLabelsDoNotCreateAConflict() {
        val absent = inspect("Report date: 2026-11-03 08:15", "Physician name: Synthetic A", "姓名", "Synthetic B")
        assertEquals(HealthOcrSourceContext(), absent)
        val same = inspect("Patient name: Synthetic A", "Patient name: Synthetic A",
            "Sample collection date/time: 2026/11/3 8:15", "Sample collection date/time: 2026/11/3 8:15")
        assertEquals(1, same.owners.size)
        assertEquals(1, same.times.size)
        assertNotNull(same.sample)
    }
}
