package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSelfEvolutionTest {
    @Test
    fun `candidate reaches review without mutating a production workspace`() {
        val runtime = FakeEvolutionRuntime()
        val store = InMemoryAgentSelfEvolutionStore()
        val events = mutableListOf<AgentNativeJsonObject>()
        var now = 1_000L
        val manager = AgentSelfEvolutionManager(
            store,
            runtime,
            AgentSelfEvolutionEventSink(events::add),
            clock = { ++now }
        )
        val created = manager.create(
            problem = "Repair Android message state",
            scope = listOf("apps/android/app"),
            acceptance = listOf("The focused test passes")
        )

        val prepared = manager.prepare(created.taskId)
        val completed = manager.applyPatchAndValidate(created.taskId, VALID_PATCH)

        assertEquals(AgentSelfEvolutionStatus.RUNNING, prepared.status)
        assertEquals(AgentSelfEvolutionStatus.WAITING_APPROVAL, completed.status)
        assertEquals(runtime.baseCommit, completed.baseCommit)
        assertEquals(runtime.candidateCommit, completed.candidateCommit)
        assertEquals(listOf("apps/android/app/src/main/Fix.kt"), completed.attempts.single().changedFiles)
        assertTrue(completed.attempts.single().gates.all { it.status == AgentSelfEvolutionGateStatus.PASSED })
        assertEquals(64, completed.approvalHash.length)
        assertFalse(runtime.productionWorkspaceTouched)
        assertTrue(events.any { it["event"] == "candidate_ready" })
        assertFalse(completed.publicValue().toString().contains(prepared.attempts.single().workspaceId))
    }

    @Test
    fun `out of scope patch is discarded and offered for replan`() {
        val runtime = FakeEvolutionRuntime(
            changedFiles = listOf("apps/desktop/src/main.js")
        )
        val manager = manager(runtime, maxAttempts = 2)
        val prepared = manager.prepare(runtime.taskId)
        val result = manager.applyPatchAndValidate(prepared.taskId, VALID_PATCH)

        assertEquals(AgentSelfEvolutionStatus.PROPOSED, result.status)
        assertEquals("scope_violation", result.lastErrorCode)
        assertEquals(1, runtime.discarded.size)
        assertTrue(result.attempts.single().failureSummary.contains("outside the declared scope"))
    }

    @Test
    fun `quality gate failure consumes bounded attempts then stops`() {
        val runtime = FakeEvolutionRuntime(
            gates = listOf(
                AgentSelfEvolutionGate(
                    id = "android-unit-build",
                    status = AgentSelfEvolutionGateStatus.FAILED,
                    exitCode = 1,
                    summary = "test failed"
                )
            )
        )
        val manager = manager(runtime, maxAttempts = 2)

        manager.prepare(runtime.taskId)
        val first = manager.applyPatchAndValidate(runtime.taskId, VALID_PATCH)
        assertEquals(AgentSelfEvolutionStatus.PROPOSED, first.status)

        manager.prepare(runtime.taskId)
        val second = manager.applyPatchAndValidate(runtime.taskId, VALID_PATCH)
        assertEquals(AgentSelfEvolutionStatus.FAILED, second.status)
        assertEquals(2, second.attempts.size)
        assertEquals(2, runtime.discarded.size)
    }

    @Test
    fun `missing local runtime blocks honestly without claiming success`() {
        val runtime = FakeEvolutionRuntime(
            prepareFailure = AgentSelfEvolutionException(
                "runtime_unavailable",
                "Install the local Linux runtime",
                blocked = true
            )
        )
        val manager = manager(runtime)

        val result = manager.prepare(runtime.taskId)

        assertEquals(AgentSelfEvolutionStatus.BLOCKED, result.status)
        assertEquals("runtime_unavailable", result.lastErrorCode)
        assertTrue(result.lastError.contains("Install"))
        assertTrue(result.candidateCommit.isBlank())
    }

    @Test
    fun `missing dependency retries do not consume repair budget`() {
        val runtime = FakeEvolutionRuntime(
            prepareFailure = AgentSelfEvolutionException(
                "android_sdk_unavailable",
                "Install the Android SDK",
                blocked = true
            )
        )
        val manager = manager(runtime, maxAttempts = 1)

        repeat(4) {
            val blocked = manager.prepare(runtime.taskId)
            assertEquals(AgentSelfEvolutionStatus.BLOCKED, blocked.status)
        }
        runtime.prepareFailure = null
        val prepared = manager.prepare(runtime.taskId)
        val completed = manager.applyPatchAndValidate(runtime.taskId, VALID_PATCH)

        assertEquals(AgentSelfEvolutionStatus.RUNNING, prepared.status)
        assertEquals(AgentSelfEvolutionStatus.WAITING_APPROVAL, completed.status)
        assertEquals(5, completed.attempts.size)
    }

    @Test
    fun `desktop publishing states survive shared protocol decoding`() {
        val base = AgentSelfEvolutionTask(
            taskId = "desktop-candidate",
            problem = "Validate shared protocol state",
            reproductionSteps = emptyList(),
            scope = listOf("apps/desktop"),
            acceptance = listOf("State decodes"),
            risk = AgentSelfEvolutionRisk.MEDIUM,
            maxAttempts = 3,
            executionTarget = "desktop"
        )

        listOf(AgentSelfEvolutionStatus.PUBLISHING, AgentSelfEvolutionStatus.PUBLISHED).forEach { status ->
            val decoded = AgentSelfEvolutionJson.decode(
                AgentSelfEvolutionJson.encode(base.copy(status = status))
            )
            assertEquals(status, decoded?.status)
            assertEquals("desktop", decoded?.executionTarget)
        }
    }

    @Test
    fun `missing Android SDK during validation does not consume repair budget`() {
        val runtime = FakeEvolutionRuntime(
            validateFailure = AgentSelfEvolutionException(
                "android_sdk_unavailable",
                "Install the Android SDK build runtime",
                blocked = true
            )
        )
        val manager = manager(runtime, maxAttempts = 1)

        manager.prepare(runtime.taskId)
        val blocked = manager.applyPatchAndValidate(runtime.taskId, VALID_PATCH)
        assertEquals(AgentSelfEvolutionStatus.BLOCKED, blocked.status)

        runtime.validateFailure = null
        manager.prepare(runtime.taskId)
        val completed = manager.applyPatchAndValidate(runtime.taskId, VALID_PATCH)
        assertEquals(AgentSelfEvolutionStatus.WAITING_APPROVAL, completed.status)
    }

    @Test
    fun `rollback removes every disposable candidate and keeps task audit`() {
        val runtime = FakeEvolutionRuntime()
        val manager = manager(runtime)
        manager.prepare(runtime.taskId)
        manager.applyPatchAndValidate(runtime.taskId, VALID_PATCH)

        val rolledBack = manager.rollback(runtime.taskId)

        assertEquals(AgentSelfEvolutionStatus.ROLLED_BACK, rolledBack.status)
        assertTrue(rolledBack.candidateCommit.isBlank())
        assertTrue(rolledBack.approvalHash.isBlank())
        assertEquals(1, rolledBack.attempts.size)
        assertEquals(1, runtime.discarded.size)
    }

    @Test
    fun `approval hash binds commit scope risk and gate receipts`() {
        val runtime = FakeEvolutionRuntime()
        val manager = manager(runtime)
        manager.prepare(runtime.taskId)
        val candidate = manager.applyPatchAndValidate(runtime.taskId, VALID_PATCH)
        val changedCommit = candidate.copy(candidateCommit = "b".repeat(40))

        assertNotEquals(
            AgentSelfEvolutionPolicy.approvalHash(candidate),
            AgentSelfEvolutionPolicy.approvalHash(changedCommit)
        )
    }

    @Test
    fun `protected source paths cannot enter an evolution task`() {
        val runtime = FakeEvolutionRuntime()
        val store = InMemoryAgentSelfEvolutionStore()
        val manager = AgentSelfEvolutionManager(store, runtime)

        listOf("../outside", ".git/config", "apps/android/build").forEach { scope ->
            val result = runCatching {
                manager.create("Unsafe scope test", listOf(scope), listOf("Rejected"))
            }
            assertTrue(scope, result.isFailure)
        }
    }

    @Test
    fun `health summarizes durable outcomes retries gates and stale executions`() {
        val now = 1_000_000L
        val tasks = listOf(
            AgentSelfEvolutionTask(
                taskId = "published",
                problem = "Published candidate",
                reproductionSteps = emptyList(),
                scope = listOf("apps/android"),
                acceptance = listOf("Pass"),
                risk = AgentSelfEvolutionRisk.MEDIUM,
                maxAttempts = 3,
                status = AgentSelfEvolutionStatus.PUBLISHED,
                attempts = listOf(
                    AgentSelfEvolutionAttempt(
                        number = 1,
                        status = AgentSelfEvolutionStatus.FAILED,
                        workspaceId = "private-workspace-one",
                        branch = "evolution/published-a1",
                        gates = listOf(
                            AgentSelfEvolutionGate(
                                id = "unit",
                                status = AgentSelfEvolutionGateStatus.FAILED
                            )
                        ),
                        failureCode = "quality_gate_failed",
                        startedAtMillis = 100L,
                        completedAtMillis = 1_100L
                    ),
                    AgentSelfEvolutionAttempt(
                        number = 2,
                        status = AgentSelfEvolutionStatus.WAITING_APPROVAL,
                        workspaceId = "private-workspace-two",
                        branch = "evolution/published-a2",
                        gates = listOf(
                            AgentSelfEvolutionGate(
                                id = "unit",
                                status = AgentSelfEvolutionGateStatus.PASSED
                            )
                        ),
                        startedAtMillis = 2_000L,
                        completedAtMillis = 4_000L
                    )
                ),
                updatedAtMillis = now - 1_000L
            ),
            basicTask("stale-running", AgentSelfEvolutionStatus.RUNNING, now - 360_000L),
            basicTask("old-review", AgentSelfEvolutionStatus.WAITING_APPROVAL, now - 420_000L),
            basicTask(
                "blocked",
                AgentSelfEvolutionStatus.BLOCKED,
                now - 5_000L,
                lastErrorCode = "runtime_unavailable"
            ),
            basicTask("queued", AgentSelfEvolutionStatus.PROPOSED, now - 800_000L)
        )

        val health = AgentSelfEvolutionHealthAnalyzer.summarize(
            tasks,
            nowMillis = now,
            staleAfterMillis = 300_000L
        )

        assertEquals(5, health.totalTasks)
        assertEquals(1, health.queuedTasks)
        assertEquals(1, health.activeTasks)
        assertEquals(1, health.waitingReview)
        assertEquals(3, health.attentionTasks)
        assertEquals(listOf("stale-running"), health.staleTaskIds)
        assertEquals(2, health.totalAttempts)
        assertEquals(1, health.failedAttempts)
        assertEquals(1, health.retries)
        assertEquals(50, health.gatePassPercent)
        assertEquals(50, health.successPercent)
        assertEquals(1_500L, health.averageAttemptDurationMillis)
        assertEquals(420_000L, health.oldestReviewAgeMillis)
        assertEquals(1, health.failureCounts["quality_gate_failed"])
        assertEquals(1, health.failureCounts["runtime_unavailable"])
        assertFalse(health.publicValue().toString().contains("private-workspace"))
    }

    @Test
    fun `empty health report is deterministic and safe`() {
        val health = AgentSelfEvolutionHealthAnalyzer.summarize(
            emptyList(),
            nowMillis = 1_000L
        )

        assertEquals(0, health.totalTasks)
        assertEquals(0, health.gatePassPercent)
        assertEquals(0, health.successPercent)
        assertTrue(health.statusCounts.isEmpty())
        assertTrue(health.failureCounts.isEmpty())
        assertTrue(health.staleTaskIds.isEmpty())
    }

    private fun basicTask(
        taskId: String,
        status: AgentSelfEvolutionStatus,
        updatedAtMillis: Long,
        lastErrorCode: String = ""
    ): AgentSelfEvolutionTask = AgentSelfEvolutionTask(
        taskId = taskId,
        problem = "Health task",
        reproductionSteps = emptyList(),
        scope = listOf("apps/android"),
        acceptance = listOf("Pass"),
        risk = AgentSelfEvolutionRisk.MEDIUM,
        maxAttempts = 2,
        status = status,
        lastErrorCode = lastErrorCode,
        updatedAtMillis = updatedAtMillis
    )

    private fun manager(
        runtime: FakeEvolutionRuntime,
        maxAttempts: Int = 3
    ): AgentSelfEvolutionManager {
        val manager = AgentSelfEvolutionManager(InMemoryAgentSelfEvolutionStore(), runtime)
        manager.create(
            problem = "Repair Android message state",
            scope = listOf("apps/android/app"),
            acceptance = listOf("The focused test passes"),
            maxAttempts = maxAttempts,
            taskId = runtime.taskId
        )
        return manager
    }

    private class FakeEvolutionRuntime(
        val taskId: String = "evolve-test-task",
        val baseCommit: String = "a".repeat(40),
        val candidateCommit: String = "c".repeat(40),
        private val changedFiles: List<String> = listOf("apps/android/app/src/main/Fix.kt"),
        private val gates: List<AgentSelfEvolutionGate> = listOf(
            AgentSelfEvolutionGate(
                id = "git-diff-check",
                status = AgentSelfEvolutionGateStatus.PASSED
            ),
            AgentSelfEvolutionGate(
                id = "android-unit-build",
                status = AgentSelfEvolutionGateStatus.PASSED
            )
        ),
        var prepareFailure: Throwable? = null,
        var validateFailure: Throwable? = null
    ) : AgentSelfEvolutionRuntime {
        val discarded = mutableListOf<String>()
        var productionWorkspaceTouched = false

        override fun prepare(
            task: AgentSelfEvolutionTask,
            attempt: AgentSelfEvolutionAttempt,
            cancellationToken: AgentNativeToolCancellationToken
        ): AgentSelfEvolutionPrepareResult {
            prepareFailure?.let { throw it }
            return AgentSelfEvolutionPrepareResult(baseCommit, attempt.branch)
        }

        override fun applyPatch(
            task: AgentSelfEvolutionTask,
            attempt: AgentSelfEvolutionAttempt,
            unifiedDiff: String,
            cancellationToken: AgentNativeToolCancellationToken
        ): AgentSelfEvolutionPatchResult {
            assertEquals(VALID_PATCH, unifiedDiff)
            return AgentSelfEvolutionPatchResult(changedFiles)
        }

        override fun validate(
            task: AgentSelfEvolutionTask,
            attempt: AgentSelfEvolutionAttempt,
            changedFiles: List<String>,
            cancellationToken: AgentNativeToolCancellationToken
        ): List<AgentSelfEvolutionGate> {
            validateFailure?.let { throw it }
            return gates
        }

        override fun commit(
            task: AgentSelfEvolutionTask,
            attempt: AgentSelfEvolutionAttempt,
            cancellationToken: AgentNativeToolCancellationToken
        ): AgentSelfEvolutionCommitResult = AgentSelfEvolutionCommitResult(candidateCommit)

        override fun discard(task: AgentSelfEvolutionTask, attempt: AgentSelfEvolutionAttempt) {
            discarded += attempt.workspaceId
        }
    }

    private companion object {
        const val VALID_PATCH = """
            diff --git a/apps/android/app/src/main/Fix.kt b/apps/android/app/src/main/Fix.kt
            new file mode 100644
            index 0000000..1111111
            --- /dev/null
            +++ b/apps/android/app/src/main/Fix.kt
            @@ -0,0 +1 @@
            +package com.galaxyssi.chat
        """
    }
}
