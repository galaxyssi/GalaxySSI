package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** The host supplies access; model arguments can select records, never a group or member identity. */
internal object CollaborationScopedRecall {
    fun read(context: Context, input: Map<String, Any?>, access: CollaborationWorkspaceAccess): AgentNativeToolExecutionResult {
        val group = CollaborationGroupStore(context).load(access.groupId)
        if (group == null || access.personId.isNotBlank() && group.members.none { it.id == access.personId })
            return AgentNativeToolExecutionResult.failure("group_unavailable", "Group access was removed.")
        return when (input["mode"]) {
            "goal_contract" -> {
                if (input.keys.any { it !in setOf("mode", "cursor") } ||
                    input.containsKey("cursor") && input["cursor"] !is String)
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Goal contract recall accepts only mode and cursor.")
                val result = CollaborationGoalContractStore(context).read(access, input["cursor"] as? String ?: "")
                if (result.optString("status") != "ok")
                    AgentNativeToolExecutionResult.failure("goal_contract_unavailable", result.optString("reason", "Contract is unavailable."))
                else AgentNativeToolExecutionResult.success(result.toNativeObject() +
                    ("trust" to "host_goal_contract_not_comprehension_or_claim_verification"))
            }
            "evidence" -> {
                val ledger = CollaborationEvidenceLedger(context)
                val id = input["evidence_id"] as? String ?: ""
                if (id.isNotBlank()) {
                    val saved = ledger.read(access, id, input["sha256"] as? String ?: "")
                        ?: return AgentNativeToolExecutionResult.failure("evidence_unavailable", "Evidence is missing, changed or isolated from this assignment.")
                    val source = listOf("evidence_id", "sha256", "origin", "tool", "status", "observation_kind")
                        .associateWith { saved.get(it) }
                    page(saved, input, "execution_observed_not_claim_verified", mapOf(
                        "source_reference" to source,
                        "citation_guidance" to "To cite the original observation in workspace.observations, copy source_reference.evidence_id and sha256. " +
                            "galaxyssi_evidence_receipt describes this recall operation, not the original source. " +
                            "Follow next_offset to read the complete original; a reference or a read receipt is not verification."))
                } else {
                    val (refs, next) = ledger.browse(access, input["cursor"] as? String ?: "")
                    AgentNativeToolExecutionResult.success(mapOf("observations" to refs.map { it.toString() },
                        "next_cursor" to next, "trust" to "execution_observed_not_claim_verified"))
                }
            }
            "workspace" -> {
                val workspace = CollaborationResearchWorkspace(context)
                val id = input["object_id"] as? String ?: ""
                if (id.isNotBlank()) {
                    val saved = workspace.read(access, id, (input["revision"] as? Number)?.toInt() ?: 0)
                        ?: return AgentNativeToolExecutionResult.failure("object_unavailable", "Object revision is missing or isolated from this assignment.")
                    page(saved, input, "member_reported_not_verified")
                } else {
                    val result = workspace.browse(access, input["cursor"] as? String ?: "")
                    AgentNativeToolExecutionResult.success(mapOf("revisions" to result.revisions.map { it.toString() },
                        "next_cursor" to result.next, "trust" to "member_reported_not_verified"))
                }
            }
            else -> AgentNativeToolExecutionResult.failure("invalid_mode", "Use goal_contract, evidence or workspace for scoped recall.")
        }
    }

    private fun page(saved: JSONObject, input: Map<String, Any?>, trust: String,
                     metadata: Map<String, Any?> = emptyMap()): AgentNativeToolExecutionResult {
        val content = saved.toString()
        val offset = (input["offset"] as? Number)?.toInt()?.coerceIn(0, content.length) ?: 0
        val end = minOf(content.length, offset + 8_000)
        return AgentNativeToolExecutionResult.success(mapOf("content" to content.substring(offset, end),
            "total_characters" to content.length, "next_offset" to end.takeIf { it < content.length }, "trust" to trust) + metadata)
    }
}
