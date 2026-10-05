package com.galaxyssi.chat

import org.json.JSONObject

/** Test-only selection: real-provider fixtures must never inherit mutable UI defaults. */
internal class CollaborationLiveModelSelection private constructor(
    val modelId: String
) {
    fun members(codex: AgentCallableTarget): List<CollaborationMember> {
        requireAvailable(codex, modelId)
        return listOf(
            CollaborationMember(name = "Turing", agentId = codex.id, providerLabel = codex.title,
                role = "Document author and coordinator", modelId = modelId),
            CollaborationMember(name = "Curie", agentId = codex.id, providerLabel = codex.title,
                role = "Independent documentary reviewer", independentReview = true, modelId = modelId)
        )
    }

    fun context(person: CollaborationMember, group: String, stage: String): Map<String, String> {
        require(person.modelId == modelId) { "Fixture member model is not pinned" }
        return mapOf("collaboration_group_id" to group, "collaboration_name" to person.name,
            "collaboration_provider" to person.providerLabel, "collaboration_model_id" to person.modelId,
            CollaborationResearchWorkflow.PERSON to person.id, CollaborationResearchWorkflow.STAGE to stage,
            CollaborationGoalLoop.ENABLED to "1")
    }

    fun json() = JSONObject().put("format", "galaxyssi.live-model-selection.v2")
        .put("requested_model", modelId).put("served_model", JSONObject.NULL)
        .put("execution_route", "android_desktop_codex_openai")
        .put("same_model_all_members", true).put("reasoning_effort", "existing_adapter_default_not_pinned")
        .put("availability", "not_verified_by_this_record")
        .put("provenance", "requested_only_join_original_provider_receipts")

    companion object {
        const val MODEL_ARGUMENT = "collaborationModel"

        fun from(model: String?): CollaborationLiveModelSelection {
            require(model != null && Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,255}").matches(model) &&
                model.lowercase() !in setOf("auto", "default", "latest")) {
                "Explicit $MODEL_ARGUMENT model ID required; fixture will not use a default"
            }
            return CollaborationLiveModelSelection(model)
        }

        fun requireAvailable(target: AgentCallableTarget, model: String) {
            require(target.kind == AgentConnectorKind.AGENT && target.adapterType == "codex-app-server-or-cli" &&
                target.status == AgentConnectorStatus.AVAILABLE &&
                target.invocationProfile.models.any { it.id == model } &&
                target.invocationProfile.normalizedModelId(model) == model) {
                "Requested model $model is not advertised by available target ${target.id}; no substitution allowed"
            }
        }
    }
}
