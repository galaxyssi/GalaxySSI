package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentProjectHistoryRetentionPolicyTest {
    @Test
    fun `replan history keeps only the newest snapshot of the same action`() {
        val previous = action("fetch", AgentMobileProjectNativeTools.FETCH)
            .copy(status = AgentActionStatus.RUNNING, result = "starting")
        val completed = previous.copy(
            status = AgentActionStatus.COMPLETED,
            result = "fetched latest main"
        )
        val plan = supervisedPlan(listOf(previous)).copy(actions = listOf(completed))

        val retained = plan.historyForReplan()

        assertEquals(1, retained.count { it.id == "fetch" })
        assertEquals(AgentActionStatus.COMPLETED, retained.single().status)
        assertEquals("fetched latest main", retained.single().result)
    }

    @Test
    fun `ordinary replan history also removes duplicate action snapshots`() {
        val previous = action("read", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT)
        val latest = previous.copy(result = "latest file contents")
        val plan = AgentPlan(
            planId = "ordinary",
            goal = "Read a file",
            screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
            steps = emptyList(),
            actions = listOf(latest),
            actionHistory = listOf(previous)
        )

        val retained = plan.historyForReplan()

        assertEquals(listOf("read"), retained.map(AgentAction::id))
        assertEquals("latest file contents", retained.single().result)
    }

    @Test
    fun `retention keeps distinct retry attempts while deduplicating snapshots`() {
        val firstAttempt = action("fetch-1", AgentMobileProjectNativeTools.FETCH)
            .copy(status = AgentActionStatus.FAILED, result = "network unavailable")
        val duplicateSnapshot = firstAttempt.copy(result = "network route unavailable")
        val secondAttempt = action("fetch-2", AgentMobileProjectNativeTools.FETCH)

        val retained = AgentProjectHistoryRetentionPolicy.retain(
            listOf(firstAttempt, duplicateSnapshot, secondAttempt)
        )

        assertEquals(listOf("fetch-1", "fetch-2"), retained.map(AgentAction::id))
        assertEquals("network route unavailable", retained.first().result)
    }

    @Test
    fun `long supervised project keeps lifecycle milestones beyond recent history`() {
        val branch = action("branch", AgentMobileProjectNativeTools.CHECKOUT_BRANCH)
        val mutation = action("mutation", AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT)
        val verification = action(
            id = "verification",
            toolId = AgentOnDeviceRuntimeTools.EXECUTE,
            input = JSONObject()
                .put("workspace_id", "current")
                .put("verification_kind", "test")
        )
        val routine = (1..48).map { index ->
            action("read-$index", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT)
        }
        val plan = AgentPlan(
            planId = "long-project",
            goal = "Develop and publish the phone project",
            screen = ScreenContext(
                foregroundApp = "com.signalasi.chat",
                pageTitle = "SignalASI"
            ),
            steps = emptyList(),
            actions = emptyList(),
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            actionHistory = listOf(branch, mutation, verification) + routine
        )

        val retained = plan.historyForReplan()

        assertTrue(retained.any { it.id == branch.id })
        assertTrue(retained.any { it.id == mutation.id })
        assertTrue(retained.any { it.id == verification.id })
        assertEquals(48, retained.count { it.id.startsWith("read-") })
    }

    @Test
    fun `large history retains only the latest verified milestone of each lifecycle kind`() {
        val oldCommit = action("old-commit", AgentMobileProjectNativeTools.COMMIT)
        val newCommit = action("new-commit", AgentMobileProjectNativeTools.COMMIT)
        val routine = (1..60).map { index ->
            action("routine-$index", AgentPhoneNativeToolCatalog.WORKSPACE_STAT)
                .copy(result = "routine-$index:" + "x".repeat(1_200))
        }

        val retained = AgentProjectHistoryRetentionPolicy.retain(
            listOf(oldCommit, newCommit) + routine
        )

        assertTrue(retained.none { it.id == oldCommit.id })
        assertTrue(retained.any { it.id == newCommit.id })
        assertTrue(retained.size < routine.size + 2)
    }

    @Test
    fun `large history retains the latest failure for later model recovery`() {
        val failedFetch = action("failed-fetch", AgentMobileProjectNativeTools.FETCH)
            .copy(status = AgentActionStatus.FAILED, result = "network-route-unavailable")
        val routine = (1..60).map { index ->
            action("routine-$index", AgentPhoneNativeToolCatalog.WORKSPACE_STAT)
                .copy(result = "routine-$index:" + "x".repeat(1_200))
        }

        val retained = AgentProjectHistoryRetentionPolicy.retain(listOf(failedFetch) + routine)

        assertTrue(retained.any { it.id == failedFetch.id })
        assertTrue(retained.any { it.id == "routine-60" })
        assertTrue(retained.size < routine.size + 1)
    }

    @Test
    fun `compound runtime action retains source mutation and latest verification milestones`() {
        val branch = action("branch", AgentMobileProjectNativeTools.CHECKOUT_BRANCH)
        val editAndTest = action(
            id = "edit-and-test",
            toolId = AgentOnDeviceRuntimeTools.EXECUTE,
            input = JSONObject()
                .put("workspace_id", "current")
                .put("verification_kind", "test")
                .put("source", "python -c \"from pathlib import Path; Path('app.py').write_text('ok')\" && pytest")
        )
        val latestTest = action(
            id = "latest-test",
            toolId = AgentOnDeviceRuntimeTools.EXECUTE,
            input = JSONObject()
                .put("workspace_id", "current")
                .put("verification_kind", "test")
                .put("source", "pytest")
        )
        val routine = (1..45).map { index ->
            action("routine-$index", AgentPhoneNativeToolCatalog.WORKSPACE_STAT)
        }

        val retained = AgentProjectHistoryRetentionPolicy.retain(
            listOf(branch, editAndTest, latestTest) + routine
        )

        assertTrue(retained.any { it.id == branch.id })
        assertTrue(retained.any { it.id == editAndTest.id })
        assertTrue(retained.any { it.id == latestTest.id })
        assertEquals(48, retained.size)
    }

    @Test
    fun `session persistence keeps project milestones beyond the old 24 action window`() {
        val branch = action("branch", AgentMobileProjectNativeTools.CHECKOUT_BRANCH)
        val mutation = action("mutation", AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT)
        val test = action(
            id = "test",
            toolId = AgentOnDeviceRuntimeTools.EXECUTE,
            input = JSONObject()
                .put("workspace_id", "current")
                .put("verification_kind", "test")
        )
        val routine = (1..48).map { index ->
            action("read-$index", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT)
        }
        val plan = supervisedPlan(listOf(branch, mutation, test) + routine)

        val retained = AgentSessionPersistencePolicy.actionHistory(plan)

        assertTrue(retained.size > 24)
        assertTrue(retained.any { it.id == branch.id })
        assertTrue(retained.any { it.id == mutation.id })
        assertTrue(retained.any { it.id == test.id })
        assertTrue(retained.any { it.id == "read-48" })
    }

    @Test
    fun `session persistence compacts oversized project observations by semantic value`() {
        val branch = action("branch", AgentMobileProjectNativeTools.CHECKOUT_BRANCH)
            .copy(result = "branch:" + "b".repeat(4_096))
        val failedFetch = action("failed-fetch", AgentMobileProjectNativeTools.FETCH)
            .copy(status = AgentActionStatus.FAILED, result = "network:" + "f".repeat(4_096))
        val routine = (1..80).map { index ->
            action("routine-$index", AgentPhoneNativeToolCatalog.WORKSPACE_STAT)
                .copy(result = "routine-$index:" + "x".repeat(4_096))
        }

        val retained = AgentSessionPersistencePolicy.actionHistory(
            supervisedPlan(listOf(branch, failedFetch) + routine)
        )

        assertTrue(retained.any { it.id == branch.id })
        assertTrue(retained.any { it.id == failedFetch.id })
        assertTrue(retained.any { it.id == "routine-80" })
        assertTrue(retained.size < routine.size + 2)
        assertTrue(
            AgentProjectHistoryRetentionPolicy.estimatedPersistenceCharacters(retained) <=
                AgentProjectHistoryRetentionPolicy.MAX_PERSISTED_HISTORY_CHARACTERS
        )
    }

    @Test
    fun `non project session persistence remains bounded`() {
        val plan = AgentPlan(
            planId = "ordinary-chat",
            goal = "Answer a question",
            screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
            steps = emptyList(),
            actions = emptyList(),
            actionHistory = (1..60).map { index ->
                action("ordinary-$index", AgentPhoneNativeToolCatalog.WORKSPACE_STAT)
            }
        )

        val retained = AgentSessionPersistencePolicy.actionHistory(plan)

        assertEquals(24, retained.size)
        assertEquals("ordinary-37", retained.first().id)
        assertEquals("ordinary-60", retained.last().id)
    }

    private fun supervisedPlan(history: List<AgentAction>) = AgentPlan(
        planId = "durable-project",
        goal = "Develop, verify, and publish the phone project",
        screen = ScreenContext(
            foregroundApp = "com.signalasi.chat",
            pageTitle = "SignalASI"
        ),
        steps = emptyList(),
        actions = emptyList(),
        plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
        actionHistory = history
    )

    private fun action(
        id: String,
        toolId: String,
        input: JSONObject = JSONObject().put("workspace_id", "current")
    ) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = toolId,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = id,
        parameters = mapOf(
            "tool_id" to toolId,
            "input_json" to input.toString()
        ),
        result = "verified",
        requiresConfirmation = false
    )
}
