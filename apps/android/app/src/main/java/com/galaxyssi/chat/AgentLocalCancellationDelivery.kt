package com.galaxyssi.chat

import android.content.Context

internal object AgentLocalCancellationDelivery {
    /** Called only after inference/tools unwind; STOP itself is not a settled receipt. */
    fun settled(context: Context, identity: AgentLocalDispatchIdentity,
        dedicatedHistory: Boolean, managedTeam: Boolean) {
        if (dedicatedHistory) ChatHistoryStore.markOutgoingDelivery(context, identity.contactId,
            identity.sourceMessageId, stage = "cancelled", detail = "",
            status = context.getString(R.string.cloud_stream_cancelled_status))
        if (managedTeam) AgentConnectorResponseBus.publish(context, AgentConnectorResponse(
            sourceMessageId = identity.sourceMessageId, contactId = identity.contactId,
            content = context.getString(R.string.agent_status_cancelled),
            conversationId = identity.conversationId, turnId = identity.turnId, taskId = identity.taskId,
            success = false, taskStatus = "cancelled"))
    }
}
