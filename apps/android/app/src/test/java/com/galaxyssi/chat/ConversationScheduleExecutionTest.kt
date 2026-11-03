package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ConversationScheduleExecutionTest {
    @Test fun phoneAlarmUsesExistingLocalActionEvenWithoutAgent() {
        listOf("打开闹钟", "打开手机闹钟", "open alarms").forEach { goal ->
            val action = ConversationScheduleExecution.localAction(ConversationScheduleExecution.request(goal))
            assertEquals(goal, AgentActionKind.SET_ALARM, action?.kind)
        }
    }

    @Test fun explicitComputerRequestDoesNotOpenPhoneApp() {
        listOf("打开电脑上的闹钟", "open Windows calculator", "在Desktop打开记事本", "open Windows alarms").forEach { goal ->
            assertNull(goal, ConversationScheduleExecution.localAction(ConversationScheduleExecution.request(goal)))
            assertFalse(goal, ConversationScheduleExecution.expectsPhone(goal))
        }
    }

    @Test fun ordinaryResearchKeepsTheSelectedAgentRoute() {
        assertNull(RuleBasedAgentPlanner().deterministicLocalAction(ConversationScheduleExecution.request("总结今天的科技新闻")))
    }

    @Test fun modelTextAloneCannotProveAnActionSucceeded() {
        listOf("已打开闹钟", "未能打开：当前没有可控的手机设备连接。", "", "{broken}").forEach {
            assertEquals(AgentProactiveRunStatus.UNVERIFIED, ConversationScheduleExecution.remoteOutcome(it, true).status)
        }
    }

    @Test fun explicitFailureAndBlockedAreNotCompleted() {
        listOf("failed", "blocked").forEach {
            assertEquals(AgentProactiveRunStatus.FAILED, ConversationScheduleExecution.remoteOutcome(reply(it), true).status)
        }
    }

    @Test fun completionNeedsEvidenceAndMatchingDevice() {
        assertEquals(AgentProactiveRunStatus.COMPLETED, ConversationScheduleExecution.remoteOutcome(reply("completed"), true, true).status)
        assertEquals(AgentProactiveRunStatus.UNVERIFIED,
            ConversationScheduleExecution.remoteOutcome(reply("completed", evidence = ""), true).status)
        assertEquals(AgentProactiveRunStatus.FAILED,
            ConversationScheduleExecution.remoteOutcome(reply("completed", device = "desktop"), true, true).status)
        assertEquals(AgentProactiveRunStatus.FAILED,
            ConversationScheduleExecution.remoteOutcome(reply("completed"), false).status)
    }

    private fun reply(outcome: String, evidence: String = "Observed clock package", device: String = "phone") = JSONObject()
        .put("protocol", "galaxyssi.schedule-outcome.v1").put("outcome", outcome).put("summary", "Result")
        .put("evidence", evidence).put("execution_device", device).toString()

    @Test fun resultEnvelopeIsHiddenButAttachmentsRemain() {
        val rich = AgentRichContentCodec.encode(listOf(
            AgentRichBlock("result", AgentRichBlockType.JSON, text = reply("completed")),
            AgentRichBlock("file", AgentRichBlockType.FILE, uri = "content://fixture/report.pdf")))
        val visible = AgentRichContentCodec.decode(ConversationScheduleExecution.remoteRichOutput(rich, "Report ready"))
        assertEquals("Report ready", visible.first().text)
        assertEquals(AgentRichBlockType.FILE, visible.last().type)
        assertTrue(visible.none { "galaxyssi.schedule-outcome.v1" in it.text })
    }
}
