package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectObservationBatchPolicyTest {
    @Test
    fun `accepts one action of any supported kind`() {
        assertTrue(AgentSupervisedProjectObservationBatchPolicy.accepts(listOf(action("write", WRITE))))
    }

    @Test
    fun `accepts four independent read only observations`() {
        val actions = listOf(
            action("list", AgentPhoneNativeToolCatalog.WORKSPACE_LIST, "{\"path\":\"\"}"),
            action("read", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT_BATCH, "{\"files\":[{\"path\":\"README.md\"}]}"),
            action(
                "search",
                AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT_BATCH,
                "{\"queries\":[{\"query\":\"TODO\"},{\"query\":\"FIXME\"}]}"
            ),
            action("diff", AgentMobileProjectNativeTools.DIFF)
        )

        assertTrue(AgentSupervisedProjectObservationBatchPolicy.accepts(actions))
    }

    @Test
    fun `rejects oversized duplicate dependent and mutating batches`() {
        val read = action("read", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT, "{\"path\":\"README.md\"}")
        val fiveReads = (1..5).map { index ->
            action("read-$index", AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT, "{\"path\":\"$index.txt\"}")
        }

        assertFalse(AgentSupervisedProjectObservationBatchPolicy.accepts(fiveReads))
        assertFalse(AgentSupervisedProjectObservationBatchPolicy.accepts(listOf(read, read.copy(id = "again"))))
        assertFalse(
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
    }
}
