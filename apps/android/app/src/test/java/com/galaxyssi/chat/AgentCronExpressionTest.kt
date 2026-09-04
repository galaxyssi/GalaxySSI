package com.galaxyssi.chat

import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentCronExpressionTest {
    @Test
    fun nextOccurrenceRespectsTimeZoneAndWeekdays() {
        val cron = AgentCronExpression.parse("30 9 * * mon-fri")
        val zone = AgentCronExpression.parseZone("Asia/Shanghai")
        val friday = ZonedDateTime.of(2026, 7, 24, 9, 31, 0, 0, zone)

        val result = ZonedDateTime.ofInstant(
            java.time.Instant.ofEpochMilli(cron.nextAfter(friday.toInstant().toEpochMilli(), zone.id)),
            zone
        )

        assertEquals(ZonedDateTime.of(2026, 7, 27, 9, 30, 0, 0, zone), result)
    }

    @Test
    fun dayAndWeekdayUseVixieOrSemantics() {
        val cron = AgentCronExpression.parse("0 12 1 * mon")
        val zone = AgentCronExpression.parseZone("UTC")

        assertTrue(cron.matches(ZonedDateTime.of(2026, 7, 6, 12, 0, 0, 0, zone)))
        assertTrue(cron.matches(ZonedDateTime.of(2026, 8, 1, 12, 0, 0, 0, zone)))
    }

    @Test
    fun aliasesListsAndStepsAreSupported() {
        val cron = AgentCronExpression.parse("*/15 8,12 * jan,mar 0,7")
        val zone = AgentCronExpression.parseZone("UTC")

        assertTrue(cron.matches(ZonedDateTime.of(2026, 3, 1, 12, 45, 0, 0, zone)))
        assertFalse(cron.matches(ZonedDateTime.of(2026, 3, 2, 12, 45, 0, 0, zone)))
    }

    @Test(expected = IllegalArgumentException::class)
    fun invalidValuesAreRejected() {
        AgentCronExpression.parse("60 * * * *")
    }
}
