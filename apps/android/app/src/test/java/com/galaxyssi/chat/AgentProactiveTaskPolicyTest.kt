package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentProactiveTaskPolicyTest {
    @Test
    fun intervalCatchUpIsBounded() {
        val now = 1_800_000_000_000L
        val task = intervalTask(
            policy = AgentProactivePolicy(
                misfire = AgentProactiveMisfirePolicy.CATCH_UP,
                catchUpLimit = 3
            ),
            nextRunAtMillis = now - 20L * 60L * 1_000L
        )

        val (runs, next) = AgentProactiveTaskScheduler.dueOccurrences(task, now)

        assertEquals(3, runs.size)
        assertTrue(runs.all { it.second == AgentProactiveRunStatus.QUEUED })
        assertTrue(next > now)
    }

    @Test
    fun fireOnceCollapsesMissedIntervals() {
        val now = 1_800_000_000_000L
        val task = intervalTask(
            policy = AgentProactivePolicy(misfire = AgentProactiveMisfirePolicy.FIRE_ONCE),
            nextRunAtMillis = now - 10L * 60L * 1_000L
        )

        val (runs, next) = AgentProactiveTaskScheduler.dueOccurrences(task, now)

        assertEquals(1, runs.size)
        assertTrue(next > now)
    }

    @Test
    fun teamRequiresExactlyOneLead() {
        val failure = runCatching {
            AgentProactiveAction(
                kind = AgentProactiveActionKind.SUBAGENT_TEAM,
                team = listOf(
                    AgentProactiveTeamMember("codex", AgentProactiveTeamRole.OBSERVER),
                    AgentProactiveTeamMember("hermes", AgentProactiveTeamRole.VERIFIER)
                )
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalArgumentException)
    }

    @Test
    fun goalCheckpointRequiresStableGoalId() {
        val failure = runCatching {
            AgentProactiveTrigger(
                kind = AgentProactiveTriggerKind.GOAL_CHECKPOINT,
                intervalSeconds = 300,
                goalId = ""
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalArgumentException)
    }

    private fun intervalTask(
        policy: AgentProactivePolicy,
        nextRunAtMillis: Long
    ) = AgentProactiveTask(
        taskId = "test-task",
        name = "Test task",
        trigger = AgentProactiveTrigger(
            kind = AgentProactiveTriggerKind.INTERVAL,
            intervalSeconds = 60
        ),
        action = AgentProactiveAction(
            kind = AgentProactiveActionKind.AGENT,
            targetId = "codex",
            prompt = "Check status"
        ),
        policy = policy,
        nextRunAtMillis = nextRunAtMillis
    )
}
