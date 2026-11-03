package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentTeamExecutionLocationTest {
    private val location = AgentTeamExecutionLocation("isolated-team", "run", "group", "turn", "task", "team")
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "planner", "lead")

    @Test fun roundTripPreservesExactOwnerAndDoesNotDependOnRoundOrMemberName() {
        assertEquals(location, AgentTeamExecutionLocation.decode(location.encode(), "run"))
        location.requireAccess(access)
        location.requireAccess(access.copy(round = 9, nodeId = "new-planner"))
    }

    @Test fun groupTurnAndRunCannotSelectAnotherStore() {
        listOf(access.copy(groupId = "other"), access.copy(turnId = "other"), access.copy(runId = "other")).forEach {
            assertThrows(IllegalArgumentException::class.java) { location.requireAccess(it) }
        }
    }

    @Test fun pathLikeNamespacesAndIncompleteOwnersAreRejected() {
        listOf("", "../secret", "a/b", "a\\b", ".", "x".repeat(201)).forEach {
            assertThrows(IllegalArgumentException::class.java) { location.copy(namespace = it) }
        }
        assertThrows(IllegalArgumentException::class.java) { location.copy(taskId = "") }
        assertThrows(IllegalArgumentException::class.java) { location.copy(teamId = " ") }
        assertThrows(IllegalArgumentException::class.java) { location.copy(runId = " run ") }
    }

    @Test fun corruptUnknownOrWrongKeyBindingsFailClosed() {
        assertThrows(Exception::class.java) { AgentTeamExecutionLocation.decode("not-json", "run") }
        assertThrows(IllegalArgumentException::class.java) { AgentTeamExecutionLocation.decode(location.encode(), "another-run") }
        val raw = JSONObject(location.encode()).put("format", "future")
        assertThrows(IllegalArgumentException::class.java) { AgentTeamExecutionLocation.decode(raw.toString(), "run") }
        raw.put("format", "galaxyssi.team-execution-location.v1").remove("namespace")
        assertThrows(Exception::class.java) { AgentTeamExecutionLocation.decode(raw.toString(), "run") }
    }
}
