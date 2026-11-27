package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ConversationGoalTest {
    private val g = ConversationGoal("chat", "goal", GoalRoute("local-llm", "fixture", ""), rounds = 1, inFlight = true)
    @Test fun commandsAreExplicitAndDoNotStealRegularChat() {
        assertNull(GoalCommand.parse("/goals future"))
        assertNull(GoalCommand.parse("请解释 /goal"))
        assertEquals(GoalCommand.Status, GoalCommand.parse("/goal"))
        assertEquals(GoalCommand.Pause, GoalCommand.parse("/goal 暂停"))
        assertEquals(GoalCommand.Resume("第二段再短些"), GoalCommand.parse("/goal resume 第二段再短些"))
        assertEquals(GoalCommand.Start("写第一段\n再写第二段"), GoalCommand.parse("/goal 写第一段\n再写第二段"))
        assertEquals(GoalCommand.Help, GoalCommand.parse("/goal " + "x".repeat(4001)))
    }
    @Test fun actualWorkIsRequiredAndBudgetPausesWithoutLosingProgress() {
        val raw = """{"state":"continue","result":"提纲","next":"成稿"}"""
        val paused = g.copy(rounds = g.allowance).accept(raw)
        assertEquals(GoalPhase.PAUSED, paused.phase)
        assertEquals("提纲", paused.checkpoints.single())
        assertEquals(paused, ConversationGoal.decode(paused.json().toString()))
        assertEquals(GoalPhase.BLOCKED, g.copy(checkpoints = listOf("提纲")).accept(raw).phase)
        assertTrue(runCatching { g.accept("""{"state":"done","result":""}""") }.isFailure)
        assertTrue(runCatching { g.accept("not JSON") }.isFailure)
    }
    @Test fun approvalCannotBeSubstitutedWithACompletedResult() {
        val waiting = g.accept("""{"state":"blocked","result":"","next":"请提供原文"}""")
        assertEquals(GoalPhase.BLOCKED, waiting.phase)
        assertEquals("请提供原文", waiting.next)
        assertFalse(waiting.terminal)
        val candidate = g.accept("""{"state":"done","result":"完整成果"}""")
        assertFalse(candidate.terminal); assertTrue(candidate.review)
        val verified = """{"state":"verified","result":"","next":""}"""
        assertTrue(runCatching { g.accept(verified) }.isFailure)
        assertTrue(candidate.copy(inFlight = true).accept(verified).terminal)
    }
}
