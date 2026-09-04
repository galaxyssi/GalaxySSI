package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class AgentPlanReplanHistoryCacheTest {
    @Test
    fun sameImmutablePlanListsCompileHistoryOnce() {
        val actionHistory = listOf(action("observed"))
        val actions = listOf(action("completed"))
        val compilations = AtomicInteger()
        val compiler = { history: List<AgentAction>, current: List<AgentAction>, _: String ->
            compilations.incrementAndGet()
            history + current
        }

        val first = AgentPlanReplanHistoryCache.resolve(
            actionHistory,
            actions,
            PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            compiler
        )
        val second = AgentPlanReplanHistoryCache.resolve(
            actionHistory,
            actions,
            PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            compiler
        )

        assertSame(first, second)
        assertEquals(1, compilations.get())
    }

    @Test
    fun newActionSnapshotCannotReuseOlderReplanHistory() {
        val actionHistory = listOf(action("observed"))
        val firstActions = listOf(action("running"))
        val completedActions = listOf(action("completed"))
        val compilations = AtomicInteger()
        val compiler = { history: List<AgentAction>, current: List<AgentAction>, _: String ->
            compilations.incrementAndGet()
            history + current
        }

        val first = AgentPlanReplanHistoryCache.resolve(
            actionHistory,
            firstActions,
            PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            compiler
        )
        val completed = AgentPlanReplanHistoryCache.resolve(
            actionHistory,
            completedActions,
            PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            compiler
        )

        assertEquals(listOf("observed", "running"), first.map(AgentAction::id))
        assertEquals(listOf("observed", "completed"), completed.map(AgentAction::id))
        assertEquals(2, compilations.get())
    }

    private fun action(id: String) = AgentAction(
        id = id,
        kind = AgentActionKind.DRAFT_PLAN,
        target = id,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = id,
        requiresConfirmation = false
    )
}
