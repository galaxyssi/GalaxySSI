package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

object AgentRemoteReputation {
    fun ingest(
        context: Context,
        envelope: JSONObject
    ): AgentReputationRecordResult? {
        val receiptJson = envelope.optJSONObject("execution_receipt") ?: return null
        val receipt = AgentReputationWireCodec.decodeReceipt(receiptJson)
            ?: return AgentReputationRecordResult(false, reason = "receipt_invalid")
        bindingFailure(envelope, receipt)?.let { reason ->
            return AgentReputationRecordResult(false, reason = reason)
        }
        return AgentReputationLedger.encrypted(context.applicationContext).record(receipt)
    }

    internal fun bindingFailure(
        envelope: JSONObject,
        receipt: AgentSignedExecutionReceipt
    ): String? {
        val desktopId = envelope.optString("desktop_id").trim()
        val taskId = envelope.optString("task_id").trim()
        val rawAgentId = envelope.optString("agent_id").trim()
        val contactId = envelope.optString("contact_id").trim()
        val expectedAgentId = if (contactId.startsWith("desktop_") && ':' in contactId) {
            contactId
        } else {
            "$desktopId:$rawAgentId"
        }
        if (desktopId.isBlank() || taskId.isBlank() || rawAgentId.isBlank() ||
            receipt.signerId != desktopId ||
            receipt.installationId != desktopId ||
            receipt.executorFailureDomain != desktopId ||
            receipt.agentId != expectedAgentId ||
            receipt.taskIdHash != agentReputationSha256(taskId.toByteArray(Charsets.UTF_8))
        ) {
            return "receipt_binding_invalid"
        }
        return null
    }
}
