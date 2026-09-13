package com.galaxyssi.chat

/** Admission is based on the durable request and workspace, not a UI's selected conversation. */
internal object AgentConnectorBackgroundIdentity {
    fun matches(response: AgentConnectorResponse, identity: AgentConnectorResponseIdentity,
                workspace: AgentWorkspace): Boolean =
        response.sourceMessageId > 0 && response.contactId.isNotBlank() &&
            identity.conversationId.isNotBlank() && identity.turnId.isNotBlank() && identity.taskId.isNotBlank() &&
            workspace.workspaceId == identity.turnId && workspace.conversationId == identity.conversationId &&
            !workspace.cancellationRequested &&
            (response.conversationId.isBlank() || response.conversationId == identity.conversationId) &&
            (response.turnId.isBlank() || response.turnId == identity.turnId) &&
            (response.taskId.isBlank() || response.taskId == identity.taskId)
}
