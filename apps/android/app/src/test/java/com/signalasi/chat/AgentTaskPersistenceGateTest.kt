package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTaskPersistenceGateTest {
    @Test
    fun `identical task state is persisted once`() {
        val gate = AgentTaskPersistenceGate()
        var writes = 0

        assertTrue(gate.persistIfChanged(fingerprint()) { writes += 1 })
        assertFalse(gate.persistIfChanged(fingerprint()) { writes += 1 })

        assertEquals(1, writes)
    }

    @Test
    fun `changed result or action log is persisted`() {
        val gate = AgentTaskPersistenceGate()
        var writes = 0

        gate.persistIfChanged(fingerprint()) { writes += 1 }
        gate.persistIfChanged(fingerprint(result = "done")) { writes += 1 }
        gate.persistIfChanged(fingerprint(actionLog = listOf("completed: build"))) { writes += 1 }

        assertEquals(3, writes)
    }

    @Test
    fun `failed persistence remains retryable`() {
        val gate = AgentTaskPersistenceGate()
        val state = fingerprint()

        assertThrows(IllegalStateException::class.java) {
            gate.persistIfChanged(state) { error("disk unavailable") }
        }

        assertTrue(gate.persistIfChanged(state) { })
    }

    private fun fingerprint(
        result: String = "running",
        actionLog: List<String> = listOf("running: build")
    ) = AgentTaskPersistenceFingerprint(
        taskId = "task-1",
        sessionId = "session-1",
        goal = "Build the project",
        phase = AgentPhase.EXECUTING,
        routeKind = AgentRouteKind.LOCAL_SYSTEM,
        targetTitle = "Phone Linux",
        risk = AgentRisk.LOW,
        blocked = false,
        executionLocationKind = AgentExecutionLocationKind.PHONE,
        executionRuntimeKind = AgentExecutionRuntimeKind.PHONE_LINUX,
        executionLocationId = "phone",
        executionLocationName = "This phone",
        executionRuntimeId = "linux",
        executionLocationTrusted = true,
        result = result,
        verification = "",
        actionLog = actionLog
    )
}
