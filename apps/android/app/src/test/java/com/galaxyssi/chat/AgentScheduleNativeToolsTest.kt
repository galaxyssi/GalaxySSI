package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentScheduleNativeToolsTest {
    private fun create() = mapOf("operation" to "create", "prompt" to "Check the synthetic status",
        "schedule_label" to "Every hour", "schedule" to mapOf("kind" to "interval", "interval_seconds" to 3600))

    @Test fun acceptsOnlyStructuredModelDecisionsNotChatPhrases() {
        listOf("Every day I read a chapter", "每天读几页书合适", "每天跑步能改善睡眠么", "每分钟检查测试状态").forEach {
            assertTrue(it, runCatching { AgentScheduleToolRequest.parse(mapOf("request" to it)) }.isFailure)
        }
        val request = AgentScheduleToolRequest.parse(create())
        assertEquals("create", request.operation)
        assertEquals(3600L, request.trigger?.intervalSeconds)
    }

    @Test fun modelCanChooseArbitraryTaskContentWithoutAnActionKeywordList() {
        val request = AgentScheduleToolRequest.parse(create() + ("prompt" to "Compare two simulated inventory reports"))
        assertEquals("Compare two simulated inventory reports", request.prompt)
    }

    @Test fun calendarScheduleRetainsExplicitTimezone() {
        val request = AgentScheduleToolRequest.parse(create() + ("schedule" to mapOf("kind" to "cron",
            "cron" to "0 9 * * 1-5", "time_zone" to "Asia/Shanghai")))
        assertEquals("0 9 * * 1-5", request.trigger?.cron)
        assertEquals("Asia/Shanghai", request.trigger?.timeZone)
    }

    @Test fun invalidOrMixedTimeFieldsFailBeforePersistence() {
        listOf(mapOf("kind" to "interval", "interval_seconds" to 0),
            mapOf("kind" to "interval", "interval_seconds" to 60.5),
            mapOf("kind" to "interval", "interval_seconds" to 60, "cron" to "0 9 * * *"),
            mapOf("kind" to "cron", "cron" to "not a cron"),
            mapOf("kind" to "cron", "cron" to "0 9 * * *", "interval_seconds" to 60),
            mapOf("kind" to "interval", "interval_seconds" to 60, "time_zone" to "Not/AZone"),
            mapOf("kind" to "manual")).forEach { schedule ->
            assertTrue(schedule.toString(), runCatching { AgentScheduleToolRequest.parse(create() + ("schedule" to schedule)) }.isFailure)
        }
    }

    @Test fun editsAndControlsRequireObservedIdentityAndRevision() {
        listOf("update", "pause", "resume").forEach { operation ->
            assertTrue(runCatching { AgentScheduleToolRequest.parse(mapOf("operation" to operation)) }.isFailure)
            val control = mapOf("operation" to operation, "task_id" to "observed-task", "expected_revision" to 2)
            val valid = if (operation == "update") control + ("prompt" to "Check B") else control
            assertEquals(operation, AgentScheduleToolRequest.parse(valid).operation)
            assertTrue(runCatching { AgentScheduleToolRequest.parse(valid + ("expected_revision" to 1.5)) }.isFailure)
        }
    }

    @Test fun createNeedsFullScheduleAndUpdateCannotSilentlyChangeItsLabel() {
        for (key in listOf("prompt", "schedule", "schedule_label"))
            assertTrue(key, runCatching { AgentScheduleToolRequest.parse(create() - key) }.isFailure)
        val update = mapOf("operation" to "update", "task_id" to "observed", "expected_revision" to 1)
        assertTrue(runCatching { AgentScheduleToolRequest.parse(update + ("schedule_label" to "Daily")) }.isFailure)
        assertTrue(runCatching { AgentScheduleToolRequest.parse(update + ("schedule" to create().getValue("schedule"))) }.isFailure)
    }

    @Test fun retriedCreationHasStableIdentityButOtherTurnsRemainSeparate() {
        val scope = AgentNativeToolInvocationContext(conversationId = "fixture", turnId = "turn")
        assertEquals(AgentScheduleNativeTools.creationId(scope, create()),
            AgentScheduleNativeTools.creationId(scope.copy(invocationId = "retry"), create()))
        assertNotEquals(AgentScheduleNativeTools.creationId(scope, create()),
            AgentScheduleNativeTools.creationId(scope.copy(turnId = "another-turn"), create()))
    }

    @Test fun modelContractDistinguishesQuestionsFromSchedulingAndDoesNotPromiseExecution() {
        val prompt = AgentPhoneInteractionPrompt.render(false)
        assertTrue(prompt.contains(AgentScheduleNativeTools.MODEL_CONTRACT))
        assertTrue(prompt.contains("question, habit or symptom report"))
        assertTrue(prompt.contains("not that its action succeeded"))
        assertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.containsAll(AgentScheduleNativeTools.toolIds))
        AgentScheduleNativeTools.toolIds.forEach {
            assertTrue(PhoneAssistantToolPolicy.allowsGeneralPhoneTool(it))
            assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(it))
            assertTrue(it in PhoneAssistantToolPolicy.directActionToolIds)
        }
    }

    @Test fun notificationsCannotEscapeAfterPauseResumeOrRemoval() {
        val task = AgentProactiveTask(name = "Synthetic schedule",
            trigger = requireNotNull(AgentScheduleToolRequest.parse(create()).trigger),
            action = AgentProactiveAction(AgentProactiveActionKind.AGENT, targetId = "fixture", prompt = "Inspect fixture"))
        assertTrue(AgentProactiveTaskNotifier.canNotify(task, task))
        assertFalse(AgentProactiveTaskNotifier.canNotify(task, null))
        assertFalse(AgentProactiveTaskNotifier.canNotify(task, task.copy(enabled = false)))
        assertFalse(AgentProactiveTaskNotifier.canNotify(task, task.copy(enabled = true, revision = task.revision + 2)))
        assertFalse(AgentProactiveTaskNotifier.canNotify(task, task.copy(taskId = "another")))
    }
}
