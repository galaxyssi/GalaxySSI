package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectObservationBatchPolicyTest {
    @Test
    fun `accepts one action of any supported kind`() {
        assertTrue(AgentSupervisedProjectObservationBatchPolicy.accepts(listOf(action("write", WRITE))))
        assertTrue(
            AgentSupervisedProjectObservationBatchPolicy.accepts(
                listOf(action("observe", AgentMobileProjectNativeTools.OBSERVE))
            )
        )
    }

    @Test
    fun `accepts up to sixty four independent read only observations`() {
        val actions = (1..AgentSupervisedProjectObservationBatchPolicy.MAX_PARALLEL_ACTIONS).map { index ->
            action(
                "read-$index",
                AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
                "{\"path\":\"src/$index.kt\"}"
            )
        }

        assertEquals(64, actions.size)
        assertTrue(AgentSupervisedProjectObservationBatchPolicy.accepts(actions))
    }

    @Test
    fun `accepts independent reads declared by tool metadata instead of a hardcoded id list`() {
        val actions = listOf(
            action("repository", AgentMobileProjectNativeTools.OBSERVE),
            action("runtime", AgentOnDeviceRuntimeTools.STATUS),
            action("runtime-workspace", AgentOnDeviceRuntimeTools.WORKSPACE_STATUS)
        )

        assertTrue(
            AgentSupervisedProjectObservationBatchPolicy.accepts(actions, "current") { toolId ->
                if (toolId in AgentOnDeviceRuntimeTools.toolIds) readOnlyRuntimeDescriptor(toolId) else null
            }
        )
    }

    @Test
    fun `rejects oversized duplicate and unscoped mutating batches`() {
        val read = action("read", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT, "{\"path\":\"README.md\"}")
        val oversizedReads = (1..65).map { index ->
            action("read-$index", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT, "{\"path\":\"$index.txt\"}")
        }

        assertFalse(AgentSupervisedProjectObservationBatchPolicy.accepts(oversizedReads))
        assertFalse(AgentSupervisedProjectObservationBatchPolicy.accepts(listOf(read, read.copy(id = "again"))))
        assertTrue(
            AgentSupervisedProjectObservationBatchPolicy.accepts(
                listOf(read, action("stat", AgentPhoneNativeToolCatalog.WORKSPACE_STAT).withDependency("read"))
            )
        )
        assertFalse(AgentSupervisedProjectObservationBatchPolicy.accepts(listOf(read, action("write", WRITE))))
        assertFalse(
            AgentSupervisedProjectObservationBatchPolicy.accepts(
                listOf(read, action("runtime", AgentOnDeviceRuntimeTools.EXECUTE))
            )
        )
    }

    @Test
    fun `accepts only disjoint resource scoped mutation batches`() {
        val left = action(
            "left",
            WRITE,
            "{\"workspace_id\":\"current\",\"path\":\"src/left.kt\"}"
        )
        val right = action(
            "right",
            WRITE,
            "{\"workspace_id\":\"current\",\"path\":\"src/right.kt\"}"
        )
        val conflict = action(
            "conflict",
            WRITE,
            "{\"workspace_id\":\"current\",\"path\":\"src/left.kt\"}"
        )

        assertTrue(acceptsMutations(listOf(left, right)))
        assertFalse(acceptsMutations(listOf(left, conflict)))
    }

    private fun acceptsMutations(actions: List<AgentAction>): Boolean =
        AgentSupervisedProjectObservationBatchPolicy.accepts(actions, "current") { toolId ->
            if (toolId == WRITE) writeDescriptor else null
        }

    @Test fun `accepts write then read on the same path with a success dependency`() {
        assertTrue(acceptsGraph(listOf(file("write", WRITE, "result.txt"),
            file("read", READ, "result.txt").withDependency("write"))))
    }

    @Test fun `accepts a transitive dependency chain including repeated verification`() {
        assertTrue(acceptsGraph(listOf(file("before", READ, "result.txt"),
            file("write", WRITE, "result.txt").withDependency("before"),
            file("after", READ, "result.txt").withDependency("write"))))
    }

    @Test fun `accepts mixed disjoint sibling reads and writes`() {
        assertTrue(acceptsGraph(listOf(file("read", READ, "left.txt"), file("write", WRITE, "right.txt"))))
    }

    @Test fun `rejects unordered same or nested resources`() {
        for (path in listOf("src", "src/result.txt")) {
            assertFalse(acceptsGraph(listOf(file("write", WRITE, "src"), file("read", READ, path))))
        }
    }

    @Test fun `rejects conflicts between a sibling and a later descendant`() {
        val actions = listOf(file("left", WRITE, "left.txt"), file("right", READ, "right.txt"),
            file("later", WRITE, "right.txt").withDependency("left"))
        assertFalse(acceptsGraph(actions))
        assertTrue(acceptsGraph(actions.dropLast(1) + actions.last().withDependency("left,right")))
    }

    @Test fun `rejects duplicate missing self and forward graph identities`() {
        val first = file("first", WRITE, "result.txt")
        val second = file("second", READ, "result.txt")
        assertFalse(acceptsGraph(listOf(first, second.copy(id = first.id))))
        for (dependency in listOf("absent", "second")) {
            assertFalse(acceptsGraph(listOf(first, second.withDependency(dependency))))
        }
        assertFalse(acceptsGraph(listOf(first.withDependency("second"), second)))
        assertFalse(acceptsGraph(listOf(first.withDependency("first"))))
    }

    @Test fun `accepts sixty four ordered actions without resetting their dependencies`() {
        val actions = (1..64).map { index -> file("$index", WRITE, "result.txt").let {
            if (index == 1) it else it.withDependency("${index - 1}")
        } }
        assertTrue(acceptsGraph(actions))
        assertFalse(acceptsGraph(actions + file("65", READ, "result.txt").withDependency("64")))
    }

    @Test fun `registered exclusive tools can be ordered but not speculatively parallelized`() {
        val tool = action("exclusive", "test.exclusive")
        val read = file("read", READ, "result.txt")
        val lookup: (String) -> AgentNativeToolDescriptor? = { id ->
            if (id == "test.exclusive") writeDescriptor.copy(id = id, capabilities = emptySet()) else descriptor(id)
        }
        assertTrue(AgentSupervisedProjectObservationBatchPolicy.accepts(listOf(tool, read.withDependency("exclusive")), "current", lookup))
        assertFalse(AgentSupervisedProjectObservationBatchPolicy.accepts(listOf(tool, read), "current", lookup))
    }

    @Test fun `rejects unsupported native output substitution and connector batches`() {
        val write = file("write", WRITE, "result.txt")
        val read = file("read", READ, "result.txt").withDependency("write")
        assertEquals("native_output_handoff", AgentSupervisedProjectObservationBatchPolicy.rejectionReason(
            listOf(write, read.copy(parameters = read.parameters + ("use_outputs_from" to "write"))), "current", ::descriptor))
        assertFalse(acceptsGraph(listOf(write, read.copy(kind = AgentActionKind.CALL_CONNECTOR))))
        assertFalse(acceptsGraph(listOf(write, action("unknown", "test.unknown").withDependency("write"))))
    }

    @Test fun `execution waits for success and blocks the dependent read on write failure`() {
        val actions = listOf(file("write", WRITE, "result.txt"), file("read", READ, "result.txt").withDependency("write"))
        val plan = AgentPlan("Write then verify", ScreenContext("Test", pageTitle = "Test"), emptyList(), actions, confirmationRequired = false)
        assertEquals(listOf("write"), AgentPlanExecutionBatchPolicy.select(plan, descriptorFor = ::descriptor).actions.map { it.id })
        val completed = plan.copy(actions = listOf(actions.first().copy(status = AgentActionStatus.COMPLETED), actions.last()))
        assertEquals(listOf("read"), AgentPlanExecutionBatchPolicy.select(completed, descriptorFor = ::descriptor).actions.map { it.id })
        val failed = plan.copy(actions = listOf(actions.first().copy(status = AgentActionStatus.FAILED), actions.last()))
            .blockActionsWithFailedDependencies()
        assertEquals(AgentActionStatus.BLOCKED, failed.actions.last().status)
        assertTrue(AgentPlanExecutionBatchPolicy.select(failed, descriptorFor = ::descriptor).actions.isEmpty())
    }

    private fun file(id: String, tool: String, path: String) = action(id, tool,
        "{\"workspace_id\":\"current\",\"path\":\"$path\"}")

    @Test fun `completion cannot skip pending siblings or descendants`() {
        val write = file("write", WRITE, "result.txt")
        val read = file("read", READ, "result.txt").withDependency("write")
        fun terminal(action: AgentAction) = action.copy(parameters = action.parameters +
            (AgentSupervisedProjectCompletionPolicy.MODEL_TERMINAL_OUTCOME_PARAMETER to "true"))
        assertFalse(acceptsGraph(listOf(terminal(write), read)))
        assertTrue(acceptsGraph(listOf(write, terminal(read))))
        val sibling = file("sibling", WRITE, "other.txt")
        assertFalse(acceptsGraph(listOf(write, sibling, terminal(read))))
        assertTrue(acceptsGraph(listOf(write, sibling, terminal(read.withDependency("write,sibling")))))
    }

    private fun descriptor(id: String): AgentNativeToolDescriptor? = when (id) {
        WRITE -> writeDescriptor
        READ -> writeDescriptor.copy(id = READ, concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY)
        else -> null
    }

    private fun acceptsGraph(actions: List<AgentAction>) =
        AgentSupervisedProjectObservationBatchPolicy.accepts(actions, "current", ::descriptor)

    private val writeDescriptor = AgentNativeToolDescriptor(
        id = WRITE,
        version = "1.0.0",
        title = "write",
        description = "write test tool",
        location = AgentNativeToolLocation.APPLICATION,
        inputSchema = AgentNativeJsonSchema.objectSchema(),
        outputSchema = AgentNativeJsonSchema.objectSchema(),
        risk = AgentNativeToolRisk.LOW,
        capabilities = setOf("workspace.file.bounded"),
        idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        concurrency = AgentNativeToolConcurrency.SERIAL
    )

    private fun readOnlyRuntimeDescriptor(toolId: String) = AgentNativeToolDescriptor(
        id = toolId,
        version = "1.0.0",
        title = "runtime status",
        description = "read-only runtime status test tool",
        location = AgentNativeToolLocation.APPLICATION,
        inputSchema = AgentNativeJsonSchema.objectSchema(),
        outputSchema = AgentNativeJsonSchema.objectSchema(),
        risk = AgentNativeToolRisk.LOW,
        capabilities = setOf("runtime.android_local"),
        idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY
    )

    private fun action(id: String, toolId: String, input: String = "{}"): AgentAction = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = toolId,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = id,
        parameters = mapOf("tool_id" to toolId, "input_json" to input),
        requiresConfirmation = false
    )

    private fun AgentAction.withDependency(id: String): AgentAction = copy(
        parameters = parameters + ("depends_on" to id)
    )

    private companion object {
        const val WRITE = AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT
        const val READ = AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT
    }
}
