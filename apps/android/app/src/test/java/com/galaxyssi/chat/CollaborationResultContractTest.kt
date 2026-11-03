package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResultContractTest {
    private val parameters = mapOf(MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true",
        "team_id" to "team", "agent_instance_id" to "member") + CollaborationResultContract.assignment("group")
    private fun action(values: Map<String, String>) = AgentAction(id = "action",
        kind = AgentActionKind.CALL_CONNECTOR, target = "member", risk = AgentRisk.LOW,
        status = AgentActionStatus.RUNNING, description = "Member assignment", parameters = values)

    @Test fun onlyCollaborationAssignmentsOptIn() {
        assertTrue(CollaborationResultContract.assignment("").isEmpty())
        assertTrue(CollaborationResultContract.assignment("  ").isEmpty())
        assertEquals(CollaborationResultContract.WORKSPACE, CollaborationResultContract.forAction(action(parameters)))
        for (key in parameters.keys) assertEquals("", CollaborationResultContract.forAction(action(parameters - key)))
    }

    @Test fun unknownOrUnmanagedContractsCannotOverrideOrdinaryDelivery() {
        for (value in listOf("", "unknown", CollaborationResultContract.WORKSPACE + " ")) {
            assertEquals("", CollaborationResultContract.forAction(action(parameters + (CollaborationResultContract.PARAMETER to value))))
        }
        assertEquals("", CollaborationResultContract.forAction(action(parameters + (MANAGED_AGENT_TEAM_ACTION_PARAMETER to "false"))))
    }

    @Test fun wireContractRequiresValidatedMemberIdentityAndSurvivesJsonRoundTrip() {
        val payload = JSONObject()
        CollaborationResultContract.encode(payload, CollaborationResultContract.forAction(action(parameters)), "team", "member")
        assertEquals(CollaborationResultContract.WORKSPACE,
            JSONObject(payload.toString()).getString(CollaborationResultContract.PARAMETER))
        for ((team, member) in listOf("" to "member", "team" to "", "bad/id" to "member", "team" to "bad/id")) {
            val rejected = JSONObject()
            CollaborationResultContract.encode(rejected, CollaborationResultContract.WORKSPACE, team, member)
            assertFalse(rejected.has(CollaborationResultContract.PARAMETER))
        }
    }

    @Test fun ordinaryMemberIdentityEncodingIsUnchanged() {
        val payload = JSONObject()
        CollaborationResultContract.encode(payload, "", " team:1 ", " member-2 ")
        assertEquals("team:1", payload.getString("team_id"))
        assertEquals("member-2", payload.getString("agent_instance_id"))
        assertFalse(payload.has(CollaborationResultContract.PARAMETER))
        for ((team, member) in listOf("t".repeat(129) to "member", "team" to "m".repeat(97))) {
            val rejected = JSONObject()
            CollaborationResultContract.encode(rejected, CollaborationResultContract.WORKSPACE, team, member)
            assertFalse(rejected.has(CollaborationResultContract.PARAMETER))
        }
    }
}
