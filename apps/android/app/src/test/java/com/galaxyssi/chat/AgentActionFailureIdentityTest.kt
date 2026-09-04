package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class AgentActionFailureIdentityTest {
    @Test
    fun identicalToolCallsShareTheSameFailureBudget() {
        val first = nativeAction("git -C /workspace rev-parse HEAD")
        val second = nativeAction("git -C /workspace rev-parse HEAD")

        assertEquals(
            AgentActionFailureIdentity.failureClass(first),
            AgentActionFailureIdentity.failureClass(second)
        )
    }

    @Test
    fun correctedToolCallsUseIndependentFailureBudgets() {
        val incorrectWorkspace = nativeAction("git -C /workspace rev-parse HEAD")
        val correctedWorkspace = nativeAction(
            "git -c safe.directory=/root/.galaxyssi-runtime/repository " +
                "-C /root/.galaxyssi-runtime/repository rev-parse HEAD"
        )

        assertNotEquals(
            AgentActionFailureIdentity.failureClass(incorrectWorkspace),
            AgentActionFailureIdentity.failureClass(correctedWorkspace)
        )
    }

    private fun nativeAction(source: String) = AgentAction(
        id = "inspect",
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = AgentOnDeviceRuntimeTools.EXECUTE,
        description = "Inspect repository",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PROPOSED,
        parameters = mapOf(
            "tool_id" to AgentOnDeviceRuntimeTools.EXECUTE,
            "input_json" to "{\"language\":\"shell\",\"source\":${quote(source)}}"
        ),
        requiresConfirmation = false
    )

    private fun quote(value: String): String = buildString {
        append('"')
        value.forEach { character ->
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                else -> append(character)
            }
        }
        append('"')
    }
}
