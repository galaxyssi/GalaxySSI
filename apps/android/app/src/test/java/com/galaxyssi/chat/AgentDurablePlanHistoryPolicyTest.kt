package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentDurablePlanHistoryPolicyTest {
    @Test
    fun durableLedgerRetains1024ActionsWhilePlannerContextStaysCompact() {
        val history = List(1_100) { index -> action("completed-$index", AgentActionStatus.COMPLETED) }
        val current = action("current", AgentActionStatus.RUNNING)
        val plan = plan(current).copy(
            revision = 4,
            actionHistory = history
        )

        val plannerHistory = plan.historyForReplan()
        val durableHistory = plan.historyForNextRevision(nextRevision = 5)

        assertEquals(AgentProjectHistoryRetentionPolicy.NON_PROJECT_RECENT_ACTION_LIMIT, plannerHistory.size)
        assertEquals(AgentLongTaskPersistenceLimits.MAX_ACTIONS, durableHistory.size)
        assertEquals("completed-77", durableHistory.first().id)
        assertEquals("current", durableHistory.last().id)
        assertEquals(AgentActionStatus.ROLLED_BACK, durableHistory.last().status)
        assertEquals("4", durableHistory.last().parameters[PLAN_REVISION_PARAMETER])
    }

    @Test
    fun durableLedgerPreservesAnActionsOriginalRevision() {
        val previous = action("r2-action", AgentActionStatus.COMPLETED).withPlanRevision(2)
        val current = action("current", AgentActionStatus.FAILED).withPlanRevision(3)
        val history = plan(current).copy(
            revision = 3,
            actionHistory = listOf(previous)
        ).historyForNextRevision(nextRevision = 4)

        assertEquals("2", history.first().parameters[PLAN_REVISION_PARAMETER])
        assertEquals("3", history.last().parameters[PLAN_REVISION_PARAMETER])
    }

    @Test
    fun removingAPendingActionRecordsItAsAdjustedAndTagsTheNewRevision() {
        val first = action("first", AgentActionStatus.PROPOSED)
        val removed = action("removed", AgentActionStatus.PROPOSED)
        val edited = AgentPlanEditor.removePendingAction(
            plan(first, removed).copy(revision = 2),
            removed.id
        )

        assertTrue(edited.success)
        val revised = requireNotNull(edited.plan)
        assertEquals(3, revised.revision)
        assertEquals("3", revised.actions.single().parameters[PLAN_REVISION_PARAMETER])
        val retired = revised.actionHistory.single { it.id == removed.id }
        assertEquals(AgentActionStatus.ROLLED_BACK, retired.status)
        assertEquals("2", retired.parameters[PLAN_REVISION_PARAMETER])
        assertEquals("superseded_by_plan_revision:3", retired.evidence)
    }

    private fun plan(vararg actions: AgentAction) = AgentPlan(
        goal = "Complete a long-running project",
        screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent"),
        steps = emptyList(),
        actions = actions.toList(),
        confirmationRequired = false
    )

    private fun action(id: String, status: AgentActionStatus) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = "phone-linux",
        risk = AgentRisk.LOW,
        status = status,
        description = "Action $id",
        requiresConfirmation = false
    )
}
