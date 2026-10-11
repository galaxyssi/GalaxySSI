package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationWorkspaceIdentityTest {
    private fun execution(person: String? = null) = AgentTeamMemberExecutionContext(
        AgentTeamMember("shared-codex", AgentDeliveryMode.RESPOND, instanceId = "coordinator",
            context = mapOf("collaboration_group_id" to "group") +
                (person?.let { mapOf(CollaborationResearchWorkflow.PERSON to it) } ?: emptyMap())),
        AgentRunRequest("group", "turn", "task", runId = "child", parentRunId = "parent", goal = "Follow up"),
        AgentSubagentContextHandoff("", emptyList(), 0, 1000, false), 0, AgentSubagentProvenance())

    @Test fun ordinaryFollowupUsesItsPersistentRosterIdentity() {
        val access = CollaborationWorkspaceAccess.from(execution())
        assertEquals("coordinator", access.personId)
        assertEquals("coordinator", access.nodeId)
        assertEquals("parent", access.runId)
        assertEquals("turn", access.turnId)
        assertEquals("group", access.groupId)
    }

    @Test fun researchStageKeepsItsPersonSeparateFromItsExecutionNode() {
        val base = execution("researcher")
        val access = CollaborationWorkspaceAccess.from(base.copy(member = base.member.copy(instanceId = "verify-node",
            context = base.member.context + (CollaborationResearchWorkflow.STAGE to "VERIFY"))))
        assertEquals("researcher", access.personId)
        assertEquals("verify-node", access.nodeId)
    }

    @Test fun sharedProviderDoesNotMergeDifferentPeople() {
        val first = execution("")
        val second = first.copy(member = first.member.copy(instanceId = "reviewer"))
        assertNotEquals(CollaborationWorkspaceAccess.from(first).personId,
            CollaborationWorkspaceAccess.from(second).personId)
    }

    @Test fun followupBindsEvidenceWithoutRelaxingOwnershipOrRevocationChecks() {
        val values = sortedMapOf<String, String>()
        val rows = object : CollaborationWorkspaceRows {
            override fun read(key: String) = values[key]
            override fun commit(changes: Map<String, String>) { values.putAll(changes) }
            override fun page(prefix: String, after: String, limit: Int) =
                values.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        }
        var allowed = true
        val ledger = CollaborationEvidenceLedger(rows) { allowed }
        val access = CollaborationWorkspaceAccess.from(execution())
        ledger.bind(71L, access)
        assertEquals(access, ledger.binding(71L, "group", "turn"))
        assertTrue(ledger.authorizes(access))
        assertFalse(ledger.authorizes(access.copy(personId = "reviewer")))
        assertNull(ledger.binding(71L, "other-group", "turn"))
        assertNull(ledger.binding(71L, "group", "other-turn"))
        allowed = false
        assertFalse(ledger.authorizes(access))
        assertThrows(CollaborationEvidenceAccessRevoked::class.java) { ledger.bind(72L, access) }
    }

    @Test fun genuinelyMissingIdentityHasAnActionableError() {
        val rows = object : CollaborationWorkspaceRows {
            override fun read(key: String): String? = null
            override fun commit(values: Map<String, String>) = Unit
            override fun page(prefix: String, after: String, limit: Int) = emptyList<String>()
        }
        val error = assertThrows(IllegalArgumentException::class.java) {
            CollaborationEvidenceLedger(rows).bind(71L, CollaborationWorkspaceAccess("group", "parent", "turn", 0L))
        }
        assertTrue(error.message.orEmpty().contains("member identities"))
    }
}
