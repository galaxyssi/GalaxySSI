package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.time.ZonedDateTime

class ConversationScheduleParserTest {
    private fun time(value: String) = ConversationScheduleParser.parseTime(value, "Asia/Shanghai")?.first

    @Test fun manualEditorStillAcceptsIntervalsAndCalendarTimes() {
        assertEquals(60L, time("每分钟")?.intervalSeconds)
        assertEquals(120L, time("每隔两分钟")?.intervalSeconds)
        assertEquals(900L, time("每十五分钟")?.intervalSeconds)
        assertEquals("0 9 * * *", time("每天早上9点")?.cron)
        assertEquals("30 9 * * *", time("每天九点半")?.cron)
        assertEquals("15 9 * * *", time("每天九点十五分")?.cron)
        assertEquals("0 18 * * 5", time("每周五18:00")?.cron)
        assertEquals("30 9 * * 1-5", time("工作日9:30")?.cron)
        assertEquals("0 18 * * 0", time("每周日晚上6点")?.cron)
        assertEquals(60L, time("Every 1 minute")?.intervalSeconds)
        assertEquals("0 9 * * *", time("daily at 09:00")?.cron)
    }

    @Test fun timeParsingDoesNotExposeAnIntentParser() {
        assertFalse(ConversationScheduleParser::class.java.declaredMethods.any { it.name == "parse" })
        assertNull(time("设置一分钟倒计时"))
        assertNull(time("每隔0分钟"))
        assertNull(time("每99999999999分钟"))
    }

    @Test fun calendarStartIsAlwaysInFuture() {
        val now = ZonedDateTime.parse("2026-10-16T09:00:30+08:00[Asia/Shanghai]").toInstant().toEpochMilli()
        val task = AgentProactiveTask(name = "fixture", trigger = requireNotNull(time("每天9点")),
            action = AgentProactiveAction(AgentProactiveActionKind.AGENT, targetId = "fixture", prompt = "check"))
        assertTrue(AgentProactiveTaskScheduler.initialNextRun(task, now) > now)
    }

    @Test fun identicalResultsStayQuietButRecoveryIsReported() {
        val previous = AgentProactiveRun("run", "task", 1, AgentProactiveRunStatus.COMPLETED, resultSummary = "Opened")
        assertFalse(ConversationScheduledTasks.resultShouldPublish(previous, "Opened", false))
        assertTrue(ConversationScheduledTasks.resultShouldPublish(previous, "Unavailable", true))
        assertTrue(ConversationScheduledTasks.resultShouldPublish(previous.copy(status = AgentProactiveRunStatus.FAILED), "Opened", false))
        assertTrue(ConversationScheduledTasks.resultShouldPublish(null, "Opened", false))
    }

    @Test fun scheduledModelSelectionSurvivesTeamPersistence() {
        assertTrue(isPersistedAgentTeamContextKey("scheduled_model_id"))
        assertTrue(isPersistedAgentTeamContextKey("scheduled_reasoning_effort"))
    }
}
