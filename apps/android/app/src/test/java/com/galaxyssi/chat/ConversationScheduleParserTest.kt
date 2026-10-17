package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test
import java.time.ZonedDateTime

class ConversationScheduleParserTest {
    private fun parse(value: String) = ConversationScheduleParser.parse(value, "Asia/Shanghai")

    @Test fun calculatorExampleCreatesRecurringWorkNotAnImmediateLaunch() {
        val command = requireNotNull(parse("每隔 1 分钟打开一次 Windows 计算器"))
        assertEquals(ConversationScheduleOperation.SAVE, command.operation)
        assertEquals(60L, command.trigger?.intervalSeconds)
        assertEquals("打开一次 Windows 计算器", command.prompt)
        assertFalse(command.createNew)
    }
    @Test fun bothApplicationsRemainInOneAssignment() {
        val command = requireNotNull(parse("每分钟打开记事本和计算器"))
        assertEquals(60L, command.trigger?.intervalSeconds)
        assertEquals("打开记事本和计算器", command.prompt)
    }
    @Test fun repeatedChineseNumberIsSupported() {
        assertEquals(120L, parse("每隔两分钟检查结果")?.trigger?.intervalSeconds)
        assertEquals(900L, parse("每十五分钟检查结果")?.trigger?.intervalSeconds)
    }
    @Test fun dailyTimeUsesCalendarSchedule() {
        val command = requireNotNull(parse("每天早上9点，帮我整理科技新闻。"))
        assertEquals("0 9 * * *", command.trigger?.cron)
        assertEquals("Asia/Shanghai", command.trigger?.timeZone)
        assertEquals("整理科技新闻", command.prompt)
        assertEquals("30 9 * * *", parse("每天九点半整理新闻")?.trigger?.cron)
        assertEquals("15 9 * * *", parse("每天九点十五分整理新闻")?.trigger?.cron)
    }
    @Test fun weeklyAndWeekdaySchedules() {
        assertEquals("0 18 * * 5", parse("每周五18:00总结本周工作")?.trigger?.cron)
        assertEquals("30 9 * * 1-5", parse("工作日9:30检查项目")?.trigger?.cron)
        assertEquals("0 18 * * 0", parse("每周日晚上6点总结")?.trigger?.cron)
    }
    @Test fun englishSchedules() {
        assertEquals(60L, parse("Every 1 minute open Calculator")?.trigger?.intervalSeconds)
        assertEquals("0 9 * * *", parse("daily at 09:00 check news")?.trigger?.cron)
    }
    @Test fun explicitNewDoesNotReplaceExistingTask() {
        assertTrue(requireNotNull(parse("新增每小时检查邮件")).createNew)
    }
    @Test fun changingOnlyContentPreservesSchedule() {
        val command = requireNotNull(parse("改成打开记事本和计算器"))
        assertEquals("打开记事本和计算器", command.prompt)
        assertNull(command.trigger)
    }
    @Test fun changingScheduleIsParsed() {
        assertEquals(120L, parse("改成每两分钟打开计算器")?.trigger?.intervalSeconds)
    }
    @Test fun stopAndResumeAreExplicitLocalControls() {
        assertEquals(ConversationScheduleOperation.PAUSE, parse("停止")?.operation)
        assertEquals(ConversationScheduleOperation.PAUSE, parse("暂停定时任务")?.operation)
        assertEquals(ConversationScheduleOperation.RESUME, parse("继续定时任务")?.operation)
        assertEquals(ConversationScheduleOperation.LIST, parse("查看定时任务")?.operation)
    }
    @Test fun questionsAndQuotedExamplesDoNotCreateSchedules() {
        listOf("每分钟心跳有什么用？", "请解释定时任务", "例如：每分钟打开计算器", "开门", "停止加热是什么意思", "继续").forEach {
            assertNull(it, parse(it))
        }
    }
    @Test fun missingActionAndInvalidTimesAreRejected() {
        listOf("每天早上9点", "每天25点打开计算器", "每隔0分钟检查邮件", "每99999999999分钟检查邮件").forEach {
            assertNull(it, parse(it))
        }
    }
    @Test fun calendarStartIsAlwaysInFuture() {
        val now = ZonedDateTime.parse("2026-10-16T09:00:30+08:00[Asia/Shanghai]").toInstant().toEpochMilli()
        val task = AgentProactiveTask(name = "fixture", trigger = requireNotNull(parse("每天9点检查")?.trigger),
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
