package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentPlanExecutionBatchPolicyTest {
    @Test
    fun selectsIndependentRunnableReadsInPlanOrder() {
        val completed = action("seed", AgentActionStatus.COMPLETED, "read", "seed")
        val plan = plan(
            completed,
            action("one", tool = "read", input = "one", dependsOn = "seed"),
            action("two", tool = "read", input = "two", dependsOn = "seed"),
            action("three", tool = "read", input = "three", dependsOn = "missing")
        )

        val batch = AgentPlanExecutionBatchPolicy.select(plan, descriptorFor = ::descriptor)

        assertTrue(batch.parallelReadOnly)
        assertEquals(listOf("one", "two"), batch.actions.map(AgentAction::id))
    }

    @Test
    fun stopsAtFirstMutationAndLeavesItSerial() {
        val plan = plan(
            action("read-one", tool = "read", input = "one"),
            action("write", tool = "write", input = "two"),
            action("read-two", tool = "read", input = "three")
        )

        val batch = AgentPlanExecutionBatchPolicy.select(plan, descriptorFor = ::descriptor)

        assertFalse(batch.parallelReadOnly)
        assertEquals(listOf("read-one"), batch.actions.map(AgentAction::id))
    }

    @Test
    fun mutationAtHeadIsAlwaysSelectedAlone() {
        val batch = AgentPlanExecutionBatchPolicy.select(
            plan(
                action("write", tool = "write", input = "one"),
                action("read", tool = "read", input = "two")
            ),
            descriptorFor = ::descriptor
        )

        assertFalse(batch.parallelReadOnly)
        assertEquals(listOf("write"), batch.actions.map(AgentAction::id))
    }

    @Test
    fun selectsIndependentSiblingFileMutationsInPlanOrder() {
        val batch = AgentPlanExecutionBatchPolicy.select(
            plan(
                scopedWrite("left", "src/left.kt"),
                scopedWrite("right", "src/right.kt")
            ),
            maxParallelMutations = 4,
            workspaceId = "workspace",
            descriptorFor = ::descriptor
        )

        assertTrue(batch.parallelResourceScoped)
        assertEquals(listOf("left", "right"), batch.actions.map(AgentAction::id))
    }

    @Test
    fun skipsConflictingMutationAndKeepsLaterIndependentWork() {
        val batch = AgentPlanExecutionBatchPolicy.select(
            plan(
                scopedWrite("first", "src/shared.kt"),
                scopedWrite("conflict", "src/shared.kt"),
                scopedWrite("independent", "test/sharedTest.kt")
            ),
            maxParallelMutations = 4,
            workspaceId = "workspace",
            descriptorFor = ::descriptor
        )

        assertTrue(batch.parallelResourceScoped)
        assertEquals(listOf("first", "independent"), batch.actions.map(AgentAction::id))
    }

    @Test
    fun duplicateObservationIsNotDispatchedConcurrently() {
        val batch = AgentPlanExecutionBatchPolicy.select(
            plan(
                action("one", tool = "read", input = "same"),
                action("two", tool = "read", input = "same")
            ),
            descriptorFor = ::descriptor
        )

        assertFalse(batch.parallelReadOnly)
        assertEquals(listOf("one"), batch.actions.map(AgentAction::id))
    }

    @Test
    fun capsParallelBatchWithoutDroppingRemainingReads() {
        val actions = (1..6).map { index ->
            action("read-$index", tool = "read", input = index.toString())
        }

        val batch = AgentPlanExecutionBatchPolicy.select(
            plan(*actions.toTypedArray()),
            maxParallelReads = 4,
            descriptorFor = ::descriptor
        )

        assertTrue(batch.parallelReadOnly)
        assertEquals(4, batch.actions.size)
        assertEquals(listOf("read-1", "read-2", "read-3", "read-4"), batch.actions.map(AgentAction::id))
    }

    @Test
    fun adaptiveLimitCanSelectMoreThanFourIndependentReads() {
        val actions = (1..24).map { index ->
            action("read-$index", tool = "read", input = index.toString())
        }

        val batch = AgentPlanExecutionBatchPolicy.select(
            plan(*actions.toTypedArray()),
            maxParallelReads = 12,
            descriptorFor = ::descriptor
        )

        assertTrue(batch.parallelReadOnly)
        assertEquals(12, batch.actions.size)
        assertEquals((1..12).map { "read-$it" }, batch.actions.map(AgentAction::id))
    }

    private fun descriptor(toolId: String): AgentNativeToolDescriptor? = when (toolId) {
        "read" -> descriptor(toolId, AgentNativeToolConcurrency.PARALLEL_READ_ONLY)
        "write" -> descriptor(toolId, AgentNativeToolConcurrency.SERIAL)
        else -> null
    }

    private fun descriptor(
        id: String,
        concurrency: AgentNativeToolConcurrency
    ) = AgentNativeToolDescriptor(
        id = "test.$id",
        version = "1.0.0",
        title = id,
        description = "$id tool",
        location = AgentNativeToolLocation.APPLICATION,
        inputSchema = AgentNativeJsonSchema.objectSchema(),
        outputSchema = AgentNativeJsonSchema.objectSchema(),
        risk = AgentNativeToolRisk.LOW,
        capabilities = if (id == "write") setOf("workspace.file.bounded") else emptySet(),
        idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        concurrency = concurrency
    )

    private fun scopedWrite(id: String, path: String): AgentAction =
        action(id, tool = "write", input = path).copy(
            parameters = mapOf(
                "tool_id" to "write",
                "input_json" to "{\"workspace_id\":\"workspace\",\"path\":\"$path\"}",
                "depends_on" to ""
            )
        )

    private fun plan(vararg actions: AgentAction) = AgentPlan(
        goal = "test",
        screen = ScreenContext(foregroundApp = "", pageTitle = ""),
        steps = emptyList(),
        actions = actions.toList()
    )

    private fun action(
        id: String,
        status: AgentActionStatus = AgentActionStatus.PENDING_CONFIRMATION,
        tool: String,
        input: String,
        dependsOn: String = ""
    ) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = tool,
        risk = AgentRisk.LOW,
        status = status,
        description = id,
        parameters = mapOf(
            "tool_id" to tool,
            "input_json" to "{\"value\":\"$input\"}",
            "depends_on" to dependsOn
        ),
        requiresConfirmation = false
    )
}
