package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentDeviceIntentTest {
    @Test fun spokenDurationsAreExactAndCompound() {
        mapOf("设置一分钟倒计时" to 60, "设置两分钟倒计时" to 120,
            "一小时二十分三十秒" to 4830, "半小时" to 1800, "一小时半" to 5400,
            "set timer one minute" to 60, "set timer 2 hours" to 7200,
            "3 minutes 20 seconds" to 200, "十五秒" to 15, "一百二十三秒" to 123).forEach { (text, seconds) ->
            assertEquals(text, seconds, AgentDeviceIntent.seconds(text))
        }
    }
    @Test fun exactShortcutDoesNotDowngradeIncompleteIntent() {
        assertEquals(60, AgentDeviceIntent.exactTimerSeconds("设置一分钟倒计时"))
        assertEquals(180, AgentDeviceIntent.exactTimerSeconds("设置3分钟倒计时"))
        assertNull(AgentDeviceIntent.exactTimerSeconds("设置倒计时"))
        assertNull(AgentDeviceIntent.exactTimerSeconds("设置一分钟导计时"))
        assertTrue(AgentDeviceIntent.requiresReasoning("设置一分钟导计时"))
        assertTrue(AgentDeviceIntent.requiresReasoning("设置倒计时"))
    }
    @Test fun invalidOrAmbiguousDurationsAreNotClampedOrPartiallyExecuted() {
        assertNull(AgentDeviceIntent.seconds("0秒"))
        assertNull(AgentDeviceIntent.seconds("999999999999小时"))
        assertNull(AgentDeviceIntent.seconds("1分钟后休息2分钟"))
        assertNull(AgentDeviceIntent.exactTimerSeconds("设置负一分钟倒计时"))
        assertNull(AgentDeviceIntent.exactTimerSeconds("设置一分半倒计时然后打开门禁"))
        assertEquals(90, AgentDeviceIntent.exactTimerSeconds("设置一分半倒计时"))
    }
    @Test fun openIsDifferentFromConfigure() {
        assertTrue(AgentDeviceIntent.explicitlyOpenTimer("打开计时器"))
        assertFalse(AgentDeviceIntent.explicitlyOpenTimer("设置一分钟倒计时"))
        assertFalse(AgentDeviceIntent.explicitlyOpenTimer("设置倒计时"))
    }
    @Test fun shortControlsHaveTypedOperations() {
        mapOf("开始" to "start", "暫停" to "pause", "继续" to "resume", "取消" to "cancel",
            "改成两分钟" to "replace", "change to 2 minutes" to "replace").forEach { (text, op) ->
            assertEquals(op, AgentDeviceIntent.followup(text))
        }
        assertNull(AgentDeviceIntent.followup("开始研究蛋白质"))
        assertNull(AgentDeviceIntent.followup("改成每两分钟打开闹钟"))
        assertNull(AgentDeviceIntent.followup("改成两分钟的会议"))
        assertNull(AgentDeviceIntent.followup("改成两分钟然后打开门禁"))
        assertNull(AgentDeviceIntent.followup("改成负一分钟"))
        assertNull(AgentDeviceIntent.followup("change to -2 minutes"))
        assertEquals("replace", AgentDeviceIntent.followup("改成两分钟的倒计时"))
    }
    @Test fun repeatingSchedulesAreNotSingleTimers() {
        assertFalse(AgentDeviceIntent.isTimerRequest("每一分钟设置倒计时"))
        assertNull(AgentDeviceIntent.exactTimerSeconds("every 1 minute start timer"))
        assertNull(ConversationScheduleParser.parse("设置一分钟倒计时"))
        assertNotNull(ConversationScheduleParser.parse("每分钟打开闹钟"))
    }
    @Test fun genericPendingContextRoutesToExecutableModelLoop() {
        val context = AgentConversationContext("one", "Pending executable goal: export a readable PDF", emptyList(), false)
        assertTrue(AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution("开始", context))
        assertFalse(AgentSupervisedProjectRoutingPolicy.isPhoneControl("开始", context))
        assertFalse(AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution("开始", context.copy(summary = "")))
    }
    @Test fun executableTypoCannotEndWithAProseOnlySuccess() {
        val context = AgentConversationContext("fixture", "", emptyList(), false)
        assertTrue(AgentSupervisedProjectRoutingPolicy.requiresPhoneReceipt("设置一分钟导计时", context))
        assertTrue(AgentSupervisedProjectRoutingPolicy.requiresPhoneReceipt("开始", context.copy(summary = "Phone operation: timer")))
        assertFalse(AgentSupervisedProjectRoutingPolicy.requiresPhoneReceipt("设置倒计时", context))
        assertFalse(AgentSupervisedProjectRoutingPolicy.requiresPhoneReceipt("开始", context))
    }
}
