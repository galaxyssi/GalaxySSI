package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationFollowupPolicyTest {
    private val coordinator = CollaborationMember(id = "lead", name = "Turing", agentId = "codex",
        providerLabel = "Codex", modelId = "chosen-model")
    private val researcher = CollaborationMember(id = "researcher", name = "Curie", agentId = "codex", providerLabel = "Codex")
    private val group = CollaborationGroup("group", listOf(coordinator, researcher), "lead", workflow = CollaborationWorkflow.RESEARCH)

    @Test fun automaticallyPopulatedRosterDoesNotBroadcastEveryFollowup() {
        val members = CollaborationFollowupPolicy.respondents(group, "Explain the results", group.requested(emptyList()))
        assertEquals(listOf("lead"), members.map { it.instanceId })
        assertEquals("chosen-model", members.single().modelId)
        assertEquals("group", members.single().collaborationGroupId)
        assertFalse(CollaborationResearchWorkflow.enabled("Research the results", members))
    }

    @Test fun explicitMentionUsesTheRequestedPersonEvenWhenTheirOldStageFinished() {
        val members = CollaborationFollowupPolicy.respondents(group, "@Curie Explain this", group.requested(emptyList()))
        assertEquals(listOf("researcher"), members.map { it.instanceId })
        assertEquals(CollaborationWorkflow.PARALLEL.name, members.single().collaborationWorkflow)
    }

    @Test fun explicitSelectionIsPreserved() {
        val members = CollaborationFollowupPolicy.respondents(group, "Explain this", listOf(researcher.requested("group")))
        assertEquals("researcher", members.single().instanceId)
    }

    @Test fun missingSelectedMemberIsReportedRatherThanSilentlyRerouted() {
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationFollowupPolicy.respondents(group, "Explain this", listOf(coordinator.requested("group").copy(persistentInstanceId = "removed")))
        }
    }

    @Test fun followupContextCannotUseAnotherGroupsBackgroundRun() {
        val background = AgentTeamExecutionSnapshot("run", "team", "other-group", "task", "codex",
            "Background goal", AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.INTERRUPTED, emptyList())
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationFollowupPolicy.context(AgentConversationContext("group", "", emptyList(), false), background)
        }
    }
}
