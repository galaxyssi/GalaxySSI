package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentConnectorBackgroundIdentityTest {
    private val response = AgentConnectorResponse(12, "peer", "Answer", "conversation", "turn", "remote-task")
    private val identity = AgentConnectorResponseIdentity("conversation", "remote-task", "turn")
    private val workspace = AgentWorkspace("turn", "turn", "conversation", "goal",
        status = AgentWorkspaceStatus.WAITING_RESPONSE)

    @Test fun matchingDurableIdentityIsAccepted() = assertTrue(matches())
    @Test fun anotherConversationIsNotRebound() = assertFalse(matches(response.copy(conversationId = "other")))
    @Test fun anotherTurnIsNotRebound() = assertFalse(matches(response.copy(turnId = "other")))
    @Test fun anotherRemoteTaskIsNotRebound() = assertFalse(matches(response.copy(taskId = "other")))
    @Test fun unknownPeerIsNotAccepted() = assertFalse(matches(response.copy(contactId = "")))
    @Test fun invalidSourceIsNotAccepted() = assertFalse(matches(response.copy(sourceMessageId = 0)))
    @Test fun workspaceMustBelongToDurableConversation() =
        assertFalse(matches(workspace = workspace.copy(conversationId = "other")))
    @Test fun workspaceMustBelongToDurableTurn() =
        assertFalse(matches(workspace = workspace.copy(workspaceId = "other")))
    @Test fun cancellationIsNotClearedByAReply() =
        assertFalse(matches(workspace = workspace.copy(cancellationRequested = true)))
    @Test fun missingRemoteIdentityIsNotGuessed() =
        assertFalse(matches(identity = identity.copy(taskId = "")))
    @Test fun missingResponseFieldsCanUseTheExistingDurableBinding() =
        assertTrue(matches(response.copy(conversationId = "", turnId = "", taskId = "")))
    @Test fun sameSourceForAnotherPeerStillRequiresTheMatchingWorkspace() {
        val other = AgentTaskIdentityPolicy.canonicalConnectorResponseIdentity(
            AgentPendingDelivery(12, "other-conversation", "other-turn", "other-task", "other-peer"),
            response.conversationId, response.taskId, response.turnId)
        assertFalse(matches(response.copy(contactId = "other-peer"), identity = other))
    }

    private fun matches(response: AgentConnectorResponse = this.response,
                        identity: AgentConnectorResponseIdentity = this.identity,
                        workspace: AgentWorkspace = this.workspace) =
        AgentConnectorBackgroundIdentity.matches(response, identity, workspace)
}
